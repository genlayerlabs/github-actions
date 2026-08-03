# Add or change an action

Each action is a directory at the repo root containing `action.yaml`. The
directory name is the reference path:

```
nix-setup/action.yaml   →  genlayerlabs/github-actions/nix-setup@main
```

## Rules

- Composite actions only. A JavaScript action needs a build step and a committed
  `node_modules`; nothing here has earned that.
- Pin third-party actions by commit SHA, never by tag. A tag can be moved, and
  these actions run with the caller's token.
- Every input needs a `description` that says what happens when it is wrong or
  empty, not just what it is.
- Never `set -x` in a step that handles a token.
- An action that talks to the cache must not fail the job when the cache is
  unavailable. Warn and continue.

## Testing

There is no way to test a composite action without running it. Push a branch and
point a consumer repo's workflow at it:

```yaml
- uses: genlayerlabs/github-actions/nix-setup@my-branch
```

Check the run log for the config the action generated before merging.

## Then

Update [actions.md](../../using/actions.md) in the same commit — it is the input
reference and goes stale silently.
