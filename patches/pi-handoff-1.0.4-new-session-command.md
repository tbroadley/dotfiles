# pi-handoff 1.0.4 patch

Patch file:
- `patches/pi-handoff-1.0.4-new-session-command.patch`

## Problem
`@ogulcancelik/pi-handoff` called `ctx.newSession()` from a tool execution context.
In pi, tools receive `ExtensionContext`, not `ExtensionCommandContext`, so `newSession()` is not available there at runtime.

Observed failure:

```text
TypeError: ctx.newSession is not a function
```

## Fix
Queue a follow-up internal command from the tool, then perform `ctx.newSession()` inside that command.

This matches pi's documented rule that session-control APIs are command-only.

## Upstream file
- `handoff.ts`

## Apply in a checkout
From the package directory containing `handoff.ts`:

```bash
patch -p0 < /path/to/pi-handoff-1.0.4-new-session-command.patch
```
