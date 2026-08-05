#!/usr/bin/env python3
"""Tests for bin/credential-broker.

Everything here exercises the half of the broker that decides — the allowlist,
the curl argv parser, grants, and what gets audited. The vault and the approval
dialog are stubbed out, so this runs anywhere, including on a machine that
deliberately has no vault on it.

    python3 tests/credential-broker.test.py
"""

import importlib.util
import json
import os
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_loader(
    "credential_broker",
    importlib.machinery.SourceFileLoader("credential_broker", str(HERE / "../bin/credential-broker")),
)
cb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cb)

SITE = "example-site.datadoghq.com"
POLICY = cb.default_policy({"DD_SITE": SITE})
TOKEN = "t" * 40


def refusal(argv, field="DD_PAT", policy=POLICY):
    """Return the refusal message for argv, or None if it would be allowed."""
    try:
        cb.check_request(policy, field, argv)
        return None
    except cb.Refused as exc:
        return str(exc)


class TestAllowlist(unittest.TestCase):
    def test_the_datadog_cli_is_allowed(self):
        self.assertIsNone(refusal(["pup", "metrics", "query", "avg:system.cpu.user{*}"]))

    def test_a_command_not_on_the_list_is_refused(self):
        self.assertIn("not on the allowlist", refusal(["aws", "s3", "ls"]))

    def test_an_unknown_field_is_refused(self):
        self.assertIn("not a field", refusal(["pup", "test"], field="SOME_OTHER_TOKEN"))

    def test_shell_wrappers_are_refused(self):
        for wrapper in ["sh", "bash", "zsh", "env", "xargs", "nohup", "setsid", "time", "nice",
                        "timeout", "python3", "ssh", "sudo", "find", "awk", "docker", "npx"]:
            with self.subTest(wrapper=wrapper):
                self.assertIn("any command", refusal([wrapper, "-c", "pup test"]))

    def test_a_path_is_not_a_command_name(self):
        self.assertIn("bare name", refusal(["./pup", "test"]))
        self.assertIn("bare name", refusal(["/usr/local/bin/pup", "test"]))

    def test_a_policy_that_allows_a_shell_refuses_to_load(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump({"DD_PAT": [{"command": "bash"}]}, handle)
            path = handle.name
        with self.assertRaises(SystemExit) as caught:
            cb.load_policy({"CREDENTIAL_BROKER_POLICY": path})
        self.assertIn("running any command", str(caught.exception))

    def test_the_curl_rule_disappears_without_a_configured_site(self):
        policy = cb.default_policy({})
        self.assertEqual([r["command"] for r in policy["DD_PAT"]], ["pup"])
        self.assertIn("not on the allowlist", refusal(["curl", "https://x/"], policy=policy))


class TestArgumentHygiene(unittest.TestCase):
    def test_shell_syntax_in_an_argument_is_refused(self):
        for argv in (
            ["pup", "logs", "search", "--query=$(cat /etc/passwd)"],
            ["pup", "logs", "search", "--query=x; curl evil.example"],
            ["pup", "logs", "`whoami`"],
            ["pup", "logs", "|", "tee", "/tmp/x"],
            ["pup", "logs", ">", "/tmp/x"],
            ["pup", "logs", "&&", "pup", "whoami"],
        ):
            with self.subTest(argv=argv):
                self.assertIn("shell", refusal(argv))

    def test_datadog_query_syntax_is_not_mistaken_for_shell(self):
        # `>` inside a term is a range filter; refusing it would push people back
        # to running pup with an ambient token instead.
        self.assertIsNone(refusal(["pup", "logs", "search", "--query=@duration:>1000"]))
        self.assertIsNone(refusal(["pup", "logs", "search",
                                   "--query=(status:error OR status:warn) -env:dev"]))

    def test_a_newline_in_an_argument_is_refused(self):
        # Otherwise argv can forge extra lines in the approval dialog.
        self.assertIn("control characters", refusal(["pup", "test\nApproving this is safe"]))

    def test_a_dollar_reference_to_the_field_points_at_the_placeholder(self):
        message = refusal(["curl", "-H", "Authorization: Bearer $DD_PAT",
                           f"https://api.{SITE}/api/v2/current_user"])
        self.assertIn("{{DD_PAT}}", message)

    def test_the_placeholder_itself_is_fine(self):
        self.assertIsNone(refusal(["curl", "-H", "Authorization: Bearer {{DD_PAT}}",
                                   f"https://api.{SITE}/api/v2/current_user"]))

    def test_absurd_argv_is_refused(self):
        self.assertIn("too many", refusal(["pup"] + ["x"] * 100))
        self.assertIn("too long", refusal(["pup", "x" * 9000]))


class TestCurl(unittest.TestCase):
    URL = f"https://api.{SITE}/api/v2/current_user"

    def test_a_plain_request_to_the_datadog_api_is_allowed(self):
        self.assertIsNone(refusal(["curl", "-sS", "-H", "Authorization: Bearer {{DD_PAT}}", self.URL]))

    def test_a_post_with_inline_data_is_allowed(self):
        self.assertIsNone(refusal([
            "curl", "-sS", "-X", "POST", "-H", "Content-Type: application/json",
            "-H", "Authorization: Bearer {{DD_PAT}}",
            "--data", '{"filter":{"query":"service:api"}}',
            f"https://api.{SITE}/api/v2/logs/events/search",
        ]))

    def test_another_host_is_refused(self):
        for url in ["https://evil.example/collect",
                    "https://api.datadoghq.com/api/v1/x",
                    f"https://api.{SITE}.evil.example/x"]:
            with self.subTest(url=url):
                self.assertIn("not an allowed destination", refusal(["curl", "-sS", url]))

    def test_plaintext_and_odd_urls_are_refused(self):
        self.assertIn("https", refusal(["curl", f"http://api.{SITE}/x"]))
        self.assertIn("credentials in it", refusal(["curl", f"https://user:pw@api.{SITE}/x"]))
        self.assertIn("default https port", refusal(["curl", f"https://api.{SITE}:8443/x"]))

    def test_exactly_one_url(self):
        self.assertIn("exactly one URL", refusal(["curl", "-sS"]))
        self.assertIn("exactly one URL", refusal(["curl", self.URL, "https://evil.example/"]))

    def test_flags_that_would_widen_this_are_refused(self):
        cases = {
            "writes a file": ["-o", "/tmp/out"],
            "writes a named file": ["-O"],
            "reads arguments the broker never sees": ["-K", "/tmp/curlrc"],
            "reads arguments from a config": ["--config", "/tmp/curlrc"],
            "sends through a proxy": ["-x", "http://evil.example:8080"],
            "follows a redirect elsewhere": ["-L"],
            "follows a redirect with credentials": ["--location-trusted"],
            "uploads a file": ["-T", "/etc/passwd"],
            "posts a form file": ["-F", "file=@/etc/passwd"],
            "skips certificate checks": ["-k"],
            "repoints the hostname": ["--resolve", f"api.{SITE}:443:1.2.3.4"],
            "talks to a socket": ["--unix-socket", "/tmp/s"],
            "writes out a report": ["-w", "%{json}"],
        }
        for description, flags in cases.items():
            with self.subTest(description):
                self.assertIn("not allowed", refusal(["curl", *flags, self.URL]))

    def test_a_file_cannot_be_smuggled_out_as_a_body(self):
        for flag in ["-d", "--data", "--data-binary", "--data-urlencode", "--json"]:
            with self.subTest(flag=flag):
                self.assertIn("not allowed", refusal(["curl", flag, "@/etc/passwd", self.URL]))

    def test_clustered_short_flags(self):
        self.assertIsNone(refusal(["curl", "-sSf", self.URL]))
        self.assertIn("not allowed", refusal(["curl", "-sSo", "/tmp/out", self.URL]))
        self.assertIsNone(refusal(["curl", "-sSXPOST", self.URL]))

    def test_inline_long_flag_values(self):
        self.assertIsNone(refusal(["curl", "--header=Authorization: Bearer {{DD_PAT}}", self.URL]))
        self.assertIn("not allowed", refusal(["curl", "--output=/tmp/out", self.URL]))

    def test_a_url_given_with_the_url_flag_is_still_checked(self):
        self.assertIsNone(refusal(["curl", "--url", self.URL]))
        self.assertIn("not an allowed destination", refusal(["curl", "--url", "https://evil.example/"]))


class TestGrants(unittest.TestCase):
    def test_the_same_command_from_the_same_session_is_covered_briefly(self):
        grants = cb.Grants(ttl=60)
        key = cb.Grants.key("DD_PAT", ["pup", "test"], "session-1", "agent")
        self.assertFalse(grants.check(key))
        grants.grant(key)
        self.assertTrue(grants.check(key))

    def test_a_different_command_is_not(self):
        grants = cb.Grants(ttl=60)
        grants.grant(cb.Grants.key("DD_PAT", ["pup", "test"], "session-1", "agent"))
        self.assertFalse(grants.check(cb.Grants.key("DD_PAT", ["pup", "logs"], "session-1", "agent")))

    def test_another_session_is_not(self):
        grants = cb.Grants(ttl=60)
        grants.grant(cb.Grants.key("DD_PAT", ["pup", "test"], "session-1", "agent"))
        self.assertFalse(grants.check(cb.Grants.key("DD_PAT", ["pup", "test"], "session-2", "agent")))

    def test_an_expired_grant_stops_covering_anything(self):
        grants = cb.Grants(ttl=-1)
        key = cb.Grants.key("DD_PAT", ["pup", "test"], "session-1", "agent")
        grants.grant(key)
        self.assertFalse(grants.check(key))


class TestRequests(unittest.TestCase):
    """The whole path, with the human and the vault stubbed."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.audit = Path(self.tmp.name) / "audit.jsonl"
        self.broker = cb.Broker({
            "CREDENTIAL_BROKER_TOKEN": TOKEN,
            "CREDENTIAL_BROKER_AUDIT": str(self.audit),
            "DD_SITE": SITE,
        })
        self.prompts = []
        self.answer = "approve"

        def fake_confirm(title, body, timeout):
            self.prompts.append((title, body))
            return self.answer

        cb.confirm = fake_confirm
        cb.notify = lambda *_: None
        self.broker.vault.field = lambda name, title: f"value-of-{name}"

    def request(self, **overrides):
        payload = {"field": "DD_PAT", "argv": ["pup", "test"], "agent": "an-agent",
                   "session": "session-1", "host": "a-box", "cwd": "/tmp", "reason": "checking"}
        payload.update(overrides)
        return self.broker.handle(payload, "100.64.0.2")

    def audit_lines(self):
        return [json.loads(line) for line in self.audit.read_text().splitlines()]

    def test_an_approved_request_returns_the_value(self):
        code, payload = self.request()
        self.assertEqual(code, 200)
        self.assertEqual(payload["value"], "value-of-DD_PAT")
        self.assertEqual(len(self.prompts), 1)

    def test_the_prompt_shows_the_exact_command_and_who_wants_it(self):
        self.request()
        title, body = self.prompts[0]
        self.assertIn("DD_PAT", title)
        self.assertIn("an-agent", title)
        self.assertIn("pup test", body)
        self.assertIn("a-box", body)
        self.assertIn("checking", body)

    def test_the_variable_the_value_lands_in_is_shown_and_audited(self):
        # The vault's name for a credential and the variable a tool reads it
        # from need not agree; whoever approves should see which is which.
        code, _ = self.request(env="DD_ACCESS_TOKEN")
        self.assertEqual(code, 200)
        _, body = self.prompts[0]
        self.assertIn("as DD_ACCESS_TOKEN", body)
        self.assertEqual(self.audit_lines()[-1]["env"], "DD_ACCESS_TOKEN")

    def test_a_junk_variable_name_is_refused_without_a_prompt(self):
        code, _ = self.request(env="PATH; rm -rf /")
        self.assertEqual(code, 403)
        self.assertEqual(self.prompts, [])

    def test_renaming_does_not_widen_the_allowlist(self):
        # --as is not a way to ask for something you could not already have.
        code, payload = self.request(argv=["bash", "-c", "x"], env="DD_ACCESS_TOKEN")
        self.assertEqual(code, 403)
        self.assertIn("any command", payload["error"])

    def test_a_denied_request_returns_nothing(self):
        self.answer = "deny"
        code, payload = self.request()
        self.assertEqual(code, 403)
        self.assertNotIn("value", payload)

    def test_an_unanswered_prompt_is_a_408_so_the_box_can_say_nobody_was_there(self):
        self.answer = "timeout"
        code, _ = self.request()
        self.assertEqual(code, 408)

    def test_a_refused_command_never_reaches_a_human(self):
        code, payload = self.request(argv=["bash", "-c", "printenv DD_PAT"])
        self.assertEqual(code, 403)
        self.assertEqual(self.prompts, [])
        self.assertIn("any command", payload["error"])

    def test_a_repeat_of_the_same_command_does_not_prompt_again(self):
        self.request()
        code, _ = self.request()
        self.assertEqual(code, 200)
        self.assertEqual(len(self.prompts), 1)
        self.assertEqual(self.audit_lines()[-1]["why"], "existing grant")

    def test_a_different_command_prompts_again(self):
        self.request()
        self.request(argv=["pup", "logs", "search"])
        self.assertEqual(len(self.prompts), 2)

    def test_every_decision_is_audited_without_the_value(self):
        self.request()
        self.answer = "deny"
        self.request(argv=["pup", "logs"])
        self.request(argv=["curl", "https://evil.example/"])
        decisions = [entry["decision"] for entry in self.audit_lines()]
        self.assertEqual(decisions, ["approved", "denied", "refused"])
        self.assertNotIn("value-of-DD_PAT", self.audit.read_text())
        self.assertIn("pup", self.audit_lines()[0]["argv"])

    def test_the_vault_field_can_be_called_something_else(self):
        # The box asks for the variable the command needs; what the vault calls
        # that field is the vault's business.
        broker = cb.Broker({
            "CREDENTIAL_BROKER_TOKEN": TOKEN,
            "CREDENTIAL_BROKER_AUDIT": str(self.audit),
            "CREDENTIAL_BROKER_VAULT_FIELD_DD_PAT": "Datadog personal access token",
            "DD_SITE": SITE,
        })
        asked = []
        broker.vault.field = lambda name, title: asked.append(name) or "pretend-token-abcdef"
        code, payload = broker.handle(
            {"field": "DD_PAT", "argv": ["pup", "test"], "session": "s"}, "100.64.0.2")
        self.assertEqual(code, 200)
        self.assertEqual(asked, ["Datadog personal access token"])
        self.assertEqual(payload["value"], "pretend-token-abcdef")

    def test_without_a_mapping_the_names_are_the_same(self):
        self.asked = []
        self.broker.vault.field = lambda name, title: self.asked.append(name) or "v" * 20
        self.request()
        self.assertEqual(self.asked, ["DD_PAT"])

    def test_a_locked_vault_is_a_refusal_not_a_crash(self):
        def locked(name, title):
            raise PermissionError("locked")

        self.broker.vault.field = locked
        code, payload = self.request()
        self.assertEqual(code, 403)
        self.assertIn("not unlocked", payload["error"])

    def test_prompt_spam_is_rate_limited_before_anyone_is_bothered(self):
        limit, _ = cb.RATE_LIMIT
        for index in range(limit):
            self.request(argv=["pup", "test", str(index)])
        code, payload = self.request(argv=["pup", "test", "over-the-limit"])
        self.assertEqual(code, 429)
        self.assertEqual(len(self.prompts), limit)

    def test_the_bearer_token_has_to_match(self):
        self.assertTrue(self.broker.authenticate(f"Bearer {TOKEN}"))
        self.assertFalse(self.broker.authenticate(f"Bearer {'t' * 39}"))
        self.assertFalse(self.broker.authenticate(""))
        self.assertFalse(self.broker.authenticate(TOKEN))

    def test_a_short_token_refuses_to_start(self):
        with self.assertRaises(SystemExit):
            cb.Broker({"CREDENTIAL_BROKER_TOKEN": "too-short"})


class TestEndToEnd(unittest.TestCase):
    """The real `with-secret` against the real broker, with the human stubbed.

    The two halves are written in different languages and talk over HTTP, so the
    thing most likely to break is the wire between them rather than either side.
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        # A policy of harmless commands, so these tests are about the wire
        # between the two halves rather than about Datadog being installed.
        policy = Path(self.tmp.name) / "policy.json"
        policy.write_text(json.dumps({"DD_PAT": [{"command": "printenv"}, {"command": "echo"}]}))
        broker = cb.Broker({
            "CREDENTIAL_BROKER_TOKEN": TOKEN,
            "CREDENTIAL_BROKER_AUDIT": str(Path(self.tmp.name) / "audit.jsonl"),
            "CREDENTIAL_BROKER_POLICY": str(policy),
        })
        self.answer = "approve"
        cb.confirm = lambda *_: self.answer
        cb.notify = lambda *_: None
        broker.vault.field = lambda name, title: "pretend-token-abcdefghij"

        class Handler(cb.Handler):
            pass

        Handler.broker = broker
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

        self.config = Path(self.tmp.name) / "box.env"
        self.config.write_text(
            f"CREDENTIAL_BROKER_URL=http://127.0.0.1:{self.server.server_address[1]}\n"
            f"CREDENTIAL_BROKER_TOKEN={TOKEN}\n"
        )
        self.config.chmod(0o600)

    def with_secret(self, *argv, token=TOKEN):
        env = {**os.environ, "CREDENTIAL_BROKER_CONFIG": str(self.config),
               "CREDENTIAL_BROKER_TOKEN": token}
        env.pop("CREDENTIAL_BROKER_URL", None)
        return subprocess.run([str(HERE / "../bin/with-secret"), *argv],
                              capture_output=True, text=True, env=env, timeout=60)

    def test_an_approved_command_runs_with_the_value_and_the_output_is_scrubbed(self):
        result = self.with_secret("DD_PAT", "--", "printenv", "DD_PAT")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "<DD_PAT redacted>")

    def test_a_command_the_allowlist_refuses_exits_3_and_says_why(self):
        result = self.with_secret("DD_PAT", "--", "bash", "-c", "echo hi")
        self.assertEqual(result.returncode, 3)
        self.assertIn("never allowed to hold a credential", result.stderr)

    def test_a_denial_exits_3_without_running_anything(self):
        self.answer = "deny"
        result = self.with_secret("DD_PAT", "--", "echo", "should-not-run")
        self.assertEqual(result.returncode, 3)
        self.assertNotIn("should-not-run", result.stdout)

    def test_an_unanswered_prompt_exits_4(self):
        self.answer = "timeout"
        result = self.with_secret("DD_PAT", "--", "echo", "hi")
        self.assertEqual(result.returncode, 4)
        self.assertIn("do not retry", result.stderr)

    def test_the_wrong_bearer_token_exits_3(self):
        result = self.with_secret("DD_PAT", "--", "echo", "hi", token="w" * 40)
        self.assertEqual(result.returncode, 3)


class TestVault(unittest.TestCase):
    """Reading one field, and what happens when the session is no good.

    The case that matters is a *stale* BW_SESSION inherited from the shell that
    started the broker, which is the normal first run for anyone whose shell
    exports one. bw exits 0 and writes something that is not an item, so the
    obvious code raises a JSON parse error the user cannot act on instead of
    asking them to unlock.
    """

    ITEM = json.dumps({"fields": [{"name": "DD_PAT", "value": "a-real-looking-token"},
                                  {"name": "OTHER", "value": ""}]})

    class Result:
        def __init__(self, returncode=0, stdout="", stderr=""):
            self.returncode, self.stdout, self.stderr = returncode, stdout, stderr

    def vault(self, *results, password="hunter2"):
        """A vault whose bw returns the given results in order.

        The password source is stubbed rather than the keychain, since where the
        password comes from is TestPasswordSource's problem, not this one's.
        """
        self.prompted = []
        vault = cb.Vault("An item", session_ttl=900,
                         password_source=lambda title: self.prompted.append(title) or password)
        vault.bw = "/fake/bw"
        vault._session = "stale-session"
        vault._touched = time.monotonic()   # a session it has no reason to doubt yet
        self.calls = []
        pending = list(results)

        def fake_run(argv, **kwargs):
            self.calls.append((argv, kwargs.get("env", {})))
            return pending.pop(0)

        original = cb.subprocess.run
        cb.subprocess.run = fake_run
        self.addCleanup(lambda: setattr(cb.subprocess, "run", original))
        return vault

    def test_a_field_is_read_out_of_the_item(self):
        vault = self.vault(self.Result(stdout=self.ITEM))
        self.assertEqual(vault.field("DD_PAT", "title"), "a-real-looking-token")
        self.assertEqual(self.prompted, [])

    def test_bw_is_told_never_to_prompt(self):
        vault = self.vault(self.Result(stdout=self.ITEM))
        vault.field("DD_PAT", "title")
        argv, env = self.calls[0]
        self.assertIn("--nointeraction", argv)
        self.assertEqual(env.get("BW_NOINTERACTION"), "1")
        self.assertEqual(env.get("BW_SESSION"), "stale-session")

    def test_the_session_key_is_never_in_argv(self):
        vault = self.vault(self.Result(stdout=self.ITEM))
        vault.field("DD_PAT", "title")
        argv, _ = self.calls[0]
        self.assertNotIn("stale-session", " ".join(argv))

    def test_a_stale_session_asks_for_the_password_instead_of_erroring(self):
        # bw exits 0 having written a prompt, not an item.
        vault = self.vault(
            self.Result(stdout="? Master password: [hidden]"),
            self.Result(stdout="fresh-session\n"),      # bw unlock
            self.Result(stdout=self.ITEM),               # the retry
        )
        self.assertEqual(vault.field("DD_PAT", "please unlock"), "a-real-looking-token")
        self.assertEqual(self.prompted, ["please unlock"])
        self.assertEqual(self.calls[2][1]["BW_SESSION"], "fresh-session")

    def test_a_locked_vault_that_says_so_also_asks(self):
        vault = self.vault(
            self.Result(returncode=1, stderr="Vault is locked."),
            self.Result(stdout="fresh-session\n"),
            self.Result(stdout=self.ITEM),
        )
        self.assertEqual(vault.field("DD_PAT", "title"), "a-real-looking-token")

    def test_refusing_the_unlock_prompt_is_a_permission_error_not_a_hang(self):
        vault = self.vault(self.Result(stdout="? Master password:"), password=None)
        with self.assertRaises(PermissionError):
            vault.field("DD_PAT", "title")

    def test_a_missing_or_empty_field_is_reported_clearly(self):
        vault = self.vault(self.Result(stdout=self.ITEM))
        with self.assertRaises(RuntimeError) as caught:
            vault.field("NOT_THERE", "title")
        self.assertIn("no field named NOT_THERE", str(caught.exception))

        vault = self.vault(self.Result(stdout=self.ITEM))
        with self.assertRaises(RuntimeError) as caught:
            vault.field("OTHER", "title")
        self.assertIn("is empty", str(caught.exception))

    def test_the_master_password_goes_through_the_environment_not_argv(self):
        vault = self.vault(
            self.Result(stdout="? Master password:"),
            self.Result(stdout="fresh-session\n"),
            self.Result(stdout=self.ITEM),
        )
        vault.field("DD_PAT", "title")
        unlock_argv, unlock_env = self.calls[1]
        self.assertIn("--passwordenv", unlock_argv)
        self.assertNotIn("hunter2", " ".join(unlock_argv))
        self.assertEqual(unlock_env.get("BW_PASSWORD"), "hunter2")


class TestPasswordSource(unittest.TestCase):
    """Where the master password comes from, and what happens when it doesn't."""

    class Result:
        def __init__(self, returncode=0, stdout="", stderr=""):
            self.returncode, self.stdout, self.stderr = returncode, stdout, stderr

    def fake_security(self, result):
        calls = []

        def fake_run(argv, **kwargs):
            calls.append(argv)
            return result

        original = cb.subprocess.run
        cb.subprocess.run = fake_run
        self.addCleanup(lambda: setattr(cb.subprocess, "run", original))
        return calls

    def fake_dialog(self, answer="typed-password"):
        asked = []
        original = cb.ask_password
        cb.ask_password = lambda title, body: asked.append((title, body)) or answer
        self.addCleanup(lambda: setattr(cb, "ask_password", original))
        return asked

    def test_the_password_comes_from_the_keychain_without_asking(self):
        calls = self.fake_security(self.Result(stdout="from-keychain\n"))
        asked = self.fake_dialog()
        source = cb.make_password_source("bw-master", account="someone")
        self.assertEqual(source("unlock please"), "from-keychain")
        self.assertEqual(asked, [])
        self.assertEqual(
            calls[0],
            ["/usr/bin/security", "find-generic-password", "-s", "bw-master",
             "-a", "someone", "-w"],
        )

    def test_a_missing_keychain_item_falls_back_to_asking(self):
        self.fake_security(self.Result(returncode=44, stderr="SecKeychainSearchCopyNext"))
        asked = self.fake_dialog()
        source = cb.make_password_source("bw-master", account="someone")
        self.assertEqual(source("unlock please"), "typed-password")
        self.assertEqual(len(asked), 1)
        title, body = asked[0]
        self.assertEqual(title, "unlock please")
        # The copy has to say which path we are on, and must not claim anything
        # about where the password is or is not kept.
        self.assertIn("keychain", body)
        self.assertNotIn("not stored", body)

    def test_the_keychain_item_is_configurable(self):
        calls = self.fake_security(self.Result(stdout="x\n"))
        cb.make_password_source("something-else", account="someone")("t")
        self.assertIn("something-else", calls[0])

    def test_the_broker_wires_the_configured_item_through(self):
        broker = cb.Broker({
            "CREDENTIAL_BROKER_TOKEN": TOKEN,
            "CREDENTIAL_BROKER_AUDIT": str(Path(tempfile.mkdtemp()) / "audit.jsonl"),
            "CREDENTIAL_BROKER_KEYCHAIN_ITEM": "another-item",
        })
        self.assertEqual(broker.keychain_item, "another-item")
        calls = self.fake_security(self.Result(stdout="x\n"))
        broker.vault.password_source("t")
        self.assertIn("another-item", calls[0])

    def test_nothing_is_unlocked_until_something_is_approved(self):
        # No warming at startup: a long-lived process holding an unlocked vault
        # that nobody asked anything of is the thing to avoid.
        vault = cb.Vault("An item", session_ttl=900)
        self.assertIsNone(vault._session)


class TestConfirmDialog(unittest.TestCase):
    """The dialog itself cannot be tested here, but its failure modes can."""

    class FakeResult:
        def __init__(self, returncode=0, stdout="", stderr=""):
            self.returncode, self.stdout, self.stderr = returncode, stdout, stderr

    def queue(self, *results):
        calls = []
        pending = list(results)

        def fake_osascript(script, *args, timeout=None):
            calls.append(script)
            return pending.pop(0)

        original = cb.osascript
        cb.osascript = fake_osascript
        self.addCleanup(lambda: setattr(cb, "osascript", original))
        return calls

    def test_an_answer_is_taken_at_face_value(self):
        calls = self.queue(self.FakeResult(stdout="approve\n"))
        self.assertEqual(cb.confirm("t", "b", 10), "approve")
        self.assertEqual(len(calls), 1)

    def test_anything_unrecognised_is_a_no(self):
        self.queue(self.FakeResult(returncode=1, stderr="User cancelled. (-128)"))
        self.assertEqual(cb.confirm("t", "b", 10), "deny")

    def test_a_missing_automation_permission_falls_back_rather_than_denying_forever(self):
        # The first run under launchd asks for Automation permission; if that is
        # refused, driving System Events fails and no dialog ever appears, which
        # would look like a silent denial forever.
        calls = self.queue(
            self.FakeResult(returncode=1, stderr="Not authorised to send Apple events (-1743)"),
            self.FakeResult(stdout="approve\n"),
        )
        self.assertEqual(cb.confirm("t", "b", 10), "approve")
        self.assertEqual(len(calls), 2)
        self.assertIn("System Events", calls[0])
        self.assertNotIn("System Events", calls[1])

    def test_a_dialog_that_never_returns_is_a_timeout(self):
        def hangs(script, *args, timeout=None):
            raise subprocess.TimeoutExpired("osascript", timeout)

        original = cb.osascript
        cb.osascript = hangs
        self.addCleanup(lambda: setattr(cb, "osascript", original))
        self.assertEqual(cb.confirm("t", "b", 1), "timeout")


class TestPromptRendering(unittest.TestCase):
    def test_arguments_are_quoted_so_the_prompt_reads_as_one_command(self):
        self.assertEqual(cb.quote_argv(["pup", "logs", "search"]), "pup logs search")
        self.assertEqual(
            cb.quote_argv(["pup", "logs", "search", "--query=service:api status:error"]),
            "pup logs search '--query=service:api status:error'",
        )
        self.assertEqual(cb.quote_argv(["pup", "it's"]), "pup 'it'\\''s'")


if __name__ == "__main__":
    unittest.main(verbosity=2)
