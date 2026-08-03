# Versioning

Consumers reference `@main`:

```yaml
- uses: genlayerlabs/github-actions/nix-setup@main
```

So a merge to `main` is a release. Every consuming repository picks it up on
their next job, with no action on their part and no review in their repo.

That is the trade the org has taken: one place to change the cache endpoint or a
pinned installer, at the cost of `main` being directly live. It means:

- A commit that breaks `nix-setup` breaks CI everywhere at once. Test on a
  branch first — see [add-an-action.md](add-an-action.md).
- Renaming or removing an input breaks consumers immediately. Add the new input,
  keep the old one working, migrate consumers, then remove it.
- Changing a default changes behaviour silently. Treat defaults as an interface.

## Why a mutable ref is acceptable here

The usual objection to `@main` is that whoever can move the ref controls what
runs next to your secrets — and consumers do hand `nix-cache-push` a push token,
which is a supply-chain credential.

What answers it is the branch protection on this repo: creations, updates and
deletions are all restricted, history must be linear, and `main` only advances
through a pull request with an approval that is dismissed when new commits land.
Moving `main` therefore costs exactly as much as merging. A SHA pin would only
add protection against a compromised maintainer account, at the price of a bump
in every consumer on every change — and pins nobody bumps are how a repo ends up
running a two-year-old action.

Third-party actions get pinned by SHA regardless, because that reasoning does not
transfer: we do not control their repos or their review. `nix-setup` pins
`cachix/install-nix-action` accordingly.

## Pinning anyway

Any ref works — branch, tag, or commit SHA:

```yaml
- uses: genlayerlabs/github-actions/nix-setup@2b5c1f0e…
```

If a consumer wants pins with automated bumps, Dependabot's `github-actions`
ecosystem updates `uses:` SHAs and does read composite `action.yaml` files. That
is a `.github/dependabot.yml` in the consumer, not a change here.

Tags exist (`v1`, `v1.0.0`) but are not the default reference and are not
maintained on every change. Cut one only if a consumer asks to pin to it:

```console
$ git tag -a v1.1.0 -m 'v1.1.0' && git push origin v1.1.0
```
