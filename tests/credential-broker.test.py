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
