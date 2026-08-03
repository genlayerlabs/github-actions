# The GenLayer Nix cache

`https://nix-cache.ygr.ai/genlayer` is a binary cache. It is **private**: every
read needs a token, in CI and on your own machine.

For CI, that token is the `cache_pull_token` input of
[`nix-setup`](../nix-setup/action.yaml), supplied from the organization secret
`NIX_CACHE_PULL_TOKEN`:

```yaml
- uses: genlayerlabs/github-actions/nix-setup@main
  with:
    cache_pull_token: ${{ secrets.NIX_CACHE_PULL_TOKEN }}
```

Without it the job does not fail — Nix reports a 401 substituter as a cache miss
and builds everything from source. `nix-setup` warns when that happens, which is
the only signal you get. A pull request from a fork gets no secrets, so it warns
and builds from source but still passes.

Everything else about the cache — getting a token, what it grants, configuring
your own machine, how it is operated — lives with the cache itself:

- [devexp-nix-cache/docs/using/](https://github.com/genlayerlabs/devexp-nix-cache/tree/main/docs/using) —
  tokens, local setup, CI details
