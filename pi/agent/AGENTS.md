Avoid using Markdown headings in your replies.

Please use the default AWS profile unless Thomas explicitly instructs otherwise.

## Expired AWS credentials

The SSO session on this host expires after a few hours, so an agent that has
been running for a while starts seeing `ExpiredToken`, `Error loading SSO
Token`, or `The SSO session associated with this profile has expired`. Fix it
yourself:

```sh
aws-sso-login              # --profile <name> for a profile other than default
```

It opens the approval page in Thomas's browser and sends him a notification,
then waits for him to click through. That takes minutes of wall clock, so give
it a long tool timeout or run it in the background and poll — don't let a 30s
default kill it mid-login. It is a no-op when the session is still good, so
running it speculatively costs nothing.

Exit 2 means the laptop is unreachable (asleep, off the network) and no login is
possible from here: say so and stop, rather than retrying in a loop. Don't ask
Thomas to run `aws sso login` for you — that is what this tool is for.

## Know which model you are

Before stating which model you are — in a PR description, a commit message, a
GitHub comment, or anywhere a repo asks you to sign your work with a model
version — read the environment:

```sh
env | grep '^PI_'   # PI_MODEL, PI_PROVIDER, PI_REASONING_LEVEL, PI_SESSION_ID
```

`PI_MODEL` is authoritative (e.g. `claude-opus-5`). Never state a model name
from memory or from your training data; you will get it wrong, usually by
naming an older model than the one you are.

## Handing work to another agent

`pru launch <name> --project <project>` starts another agent on this box and
`pru send <id> "<brief>"` gives it its task. Two things go wrong every time:

**Don't pass `--model` unless you know the provider.** This host is logged
into exactly one provider, and it is not the one you would guess from your
own model name. `--model anthropic/claude-opus-5` names a provider with no
credentials here; older builds accepted it, the child showed up as `running`,
and it never processed a word of your brief. Omit the flag and the child
inherits the host default. If you need to be explicit, read the answer from
the environment rather than memory:

```sh
pru launch helper --project <project> --model "$PI_PROVIDER/$PI_MODEL"
```

**Confirm the child actually started.** `pru send` prints "✓ message sent"
when the *server* accepted the message, not when the agent began work. Check
a minute later — `pru list` should show it out of `idle` with non-zero tokens
and cost. A child sitting at zero cost, or in `error`, never got your brief:
read its error (`pru list`, or the dashboard) and relaunch instead of waiting
for a report that isn't coming.

## Default flow for feature work

Unless told otherwise, every code change follows:

1. Agree on the change with the user.
2. Implement it on a branch.
3. Push and open a **draft** PR — `gh pr create --draft`.
4. Drive CI to green.

Step 3 is not optional and does not need to be requested: as soon as there is a
coherent change to review, push it up as a draft. Step 4 is your job, not the
user's. Take whatever routine steps the repo needs to make its checks pass,
without asking each time: starting a dev box, pulling data onto it, re-running
pipeline stages (`pivot pull`, `pivot repro`), committing and pushing
regenerated artifacts from that box. Ask first only for destructive, expensive,
or irreversible actions.

Watch the checks instead of declaring victory at push time:

```sh
gh pr checks <pr> --watch
gh run view <run-id> --log-failed   # on failure
```

Keep iterating until checks pass or you are genuinely blocked, then say what
blocked you.

## Review comments

Bots (Copilot, Codex) and humans leave review comments after a PR goes up. Poll
for them yourself; don't wait to be told they exist.

```sh
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:100) { nodes {
          id isResolved path line
          comments(first:10) { nodes { author { login } body } }
        } }
      }
    }
  }' -F owner=OWNER -F repo=REPO -F pr=NUMBER
```

After addressing a comment, push the fix and **resolve the thread**, so the
human can see at a glance what has been handled:

```sh
gh api graphql -f query='
  mutation($id:ID!) { resolveReviewThread(input:{threadId:$id}) { thread { isResolved } } }
' -F id=THREAD_ID
```

Leave a thread unresolved when you disagree with it, when it needs the user's
decision, or when you chose not to act on it — and reply in that thread saying
why. Unresolved should mean "needs a human", not "not looked at yet".

## Don't narrate in PR comments

Never post a top-level PR comment summarizing what you did, changed, or fixed.
That belongs in the PR description: `gh pr edit --body-file <file>`, kept
current as the branch evolves. Reply inside a review thread only when
responding to that specific comment.

Keeping it current means **rewriting it, not appending to it**. Re-derive the
description from the current diff each time and delete what no longer earns its
place; otherwise it ratchets from a readable page to an unreadable essay over
the life of a branch. Aim for under 500 words: what the change is, how it works,
and only those checks CI cannot run. Leave out bugs you hit on the way and
justifications for decisions nobody questioned.

## Public vs private repos: check before you push

Context from a private repo bleeds into work on a public one. Treat the
conversation history as potentially private and any public target as untrusted.

This applies to anything you author that lands in a repo other than where the
source material came from: PR titles and descriptions, commit messages, issue
and PR comments, code comments, file contents, branch names.

Before pushing, or creating/editing a PR, issue, or comment:

1. Check the target's visibility:
   `gh repo view <owner>/<repo> --json visibility -q .visibility`
2. If it is PUBLIC (or you cannot confirm it is private), write the description
   ONLY from the diff itself — what the changed files do and why. Do not pull in
   details from the conversation, other repos, or the working environment.
3. Never put in public text, unless the exact term already appears in that
   public repo: eval set / task / dataset names, internal hostnames or URLs
   (`*.internal.*`, internal dashboards), private repo names or paths,
   customer/partner names, ticket/Linear IDs, file paths from another repo, run
   or model identifiers, internal terminology.
4. If a private detail is truly needed to explain the change, generalize it
   ("an internal eval set", not its name) or ask first.

When unsure whether something is private, leave it out and say so.
