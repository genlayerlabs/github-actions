# Contributing

- [howto/setup.md](howto/setup.md) — get a working dev environment
- [howto/add-an-action.md](howto/add-an-action.md) — add or change an action
- [howto/versioning.md](howto/versioning.md) — how consumers pin, and what a merge to `main` releases

Commit style: conventional commits, enforced by the `commit-msg` hook installed
by `nix develop`.

Consumers reference `@main`, so merging here is releasing — a broken commit
breaks CI in every GenLayer repo at once. Treat the defaults (cache URL, public
key, pinned installer) as an interface, and test on a branch first.
