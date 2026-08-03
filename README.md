# github-actions

Reusable GitHub Actions shared across GenLayer repositories.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Background

Every GenLayer repository that builds with Nix needs the same two steps: install
Nix pointed at our substituters, and push what it built to the shared binary
cache. Keeping one copy here means a change to the cache endpoint, a key
rotation, or a pinned installer bump lands in one place instead of nine.

## Install

Nothing to install — reference an action by path and ref:

```yaml
- uses: genlayerlabs/github-actions/nix-setup@main
```

`@main` can be used alongside SHA, including for jobs that hold a push token. It
is a mutable ref, but `main` here is protected — creations, updates and deletions
are restricted, and it only advances through a reviewed pull request — so moving
it costs the same as merging. A SHA pin does not add much value here; see [versioning.md](docs/contributing/howto/versioning.md).

Third-party actions are a different matter and stay pinned by SHA, which is why
`nix-setup` pins `cachix/install-nix-action` that way.

## Usage

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - uses: genlayerlabs/github-actions/nix-setup@main
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          cache_pull_token: ${{ secrets.NIX_CACHE_PULL_TOKEN }}

      - run: nix build

      # Not `success()`: a job that failed late still built most of the closure,
      # and that is exactly the work a retry should not repeat.
      - if: ${{ !cancelled() }}
        uses: genlayerlabs/github-actions/nix-cache-push@main
        with:
          token: ${{ secrets.NIX_CACHE_PUSH_TOKEN }}
```

| Action                                         | Purpose                                          |
| ---------------------------------------------- | ------------------------------------------------ |
| [`nix-setup`](nix-setup/action.yaml)           | install Nix, wire up substituters and cache auth |
| [`nix-cache-push`](nix-cache-push/action.yaml) | upload locally-built paths to the cache          |

The cache is **private** — `nix-setup` needs `cache_pull_token` or it will build
everything from source. See [nix-cache.md](docs/using/nix-cache.md) for what the
tokens are, how to get one, and how to configure the same cache on your own
machine.

Full input reference: [actions.md](docs/using/actions.md).

## Contributing

See [docs/contributing/](docs/contributing/README.md).

## License

MIT © 2026 GenLayer
