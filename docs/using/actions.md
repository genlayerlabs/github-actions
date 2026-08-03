# Action reference

## nix-setup

Installs Nix (pinned installer, pinned `install-nix-action` commit) and writes
`nix.conf` with our substituters, trusted keys, and cache credentials.

| Input                       | Default                             | Description                                                                                 |
| --------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------- |
| `github_token`              | —                                   | authenticates GitHub flake inputs; they are rate-limited without one                        |
| `cache_pull_token`          | `""`                                | pull token for the GenLayer cache; empty warns and relies on the runner's own netrc, if any |
| `enable_genlayerlabs_cache` | `true`                              | set `false` to measure a cold build, or to avoid paths a bad push may have poisoned         |
| `cache_url`                 | `https://nix-cache.ygr.ai/genlayer` | substituter URL                                                                             |
| `cache_public_key`          | `genlayer:hMvP8Bk…`                 | trusted public key                                                                          |
| `extra_substituters`        | `""`                                | whitespace-separated; each needs its key below                                              |
| `extra_trusted_public_keys` | `""`                                | whitespace-separated                                                                        |
| `extra_nix_config`          | `""`                                | lines appended verbatim to `nix.conf`; later lines win                                      |

Outputs:

| Output       | Description                                                                              |
| ------------ | ---------------------------------------------------------------------------------------- |
| `netrc_path` | path to the netrc it wrote, empty when no token was given                                |
| `nix_config` | the generated `nix.conf` lines, without `netrc-file` and without your `extra_nix_config` |

These exist so a job can reuse the same credential somewhere Nix does not run
itself — most importantly a `docker build` that fetches from the cache inside
the image. Pass `netrc_path` as a BuildKit secret mounted at `/etc/nix/netrc`,
which is where Nix looks by default:

```dockerfile
RUN --mount=type=secret,id=nix_netrc,target=/etc/nix/netrc,required=false \
    nix build ...
```

Never `COPY` it or hand it to an `ARG` — both persist in the image and in
`docker history`. A secret mount does not; it is gone when the `RUN` ends.

`nix_config` omits `netrc-file` because that names a path on the runner, and
omits `extra_nix_config` because those are the caller's own settings and are
usually wrong elsewhere (a `sandbox = true` meant for the runner breaks inside a
container).

Notes:

- The cache's public key stays trusted even with the cache disabled — that
  switch stops us pulling, it does not make already-present paths untrustworthy.
- Without `cache_pull_token` the cache stays in the substituter list and the
  action warns. A self-hosted runner may already have credentials in
  `/etc/nix/netrc`, and writing `netrc-file` here would discard them; a
  GitHub-hosted runner has none, so every lookup 401s into a silent miss — which
  is what the warning is for.
- The last step probes the cache and warns if the token does not work. It never
  fails the job.

## nix-cache-push

Uploads paths this job built locally.

| Input      | Default                    | Description                                  |
| ---------- | -------------------------- | -------------------------------------------- |
| `token`    | `""`                       | push token; empty skips the step entirely    |
| `cache`    | `genlayer`                 | cache name on the server                     |
| `endpoint` | `https://nix-cache.ygr.ai` | attic server                                 |
| `include`  | `genlayer\|genvm`          | regex on the store path name, hash stripped  |
| `exclude`  | `""`                       | regex on the full store path; empty disables |

Notes:

- Selects paths by Nix's `ultimate` flag — "built on this machine" — which is
  exactly the set worth uploading. Anything else came from a substituter that
  already has it.
- Guard the step with `if: ${{ !cancelled() }}`, not the default `success()`. A
  job that failed late still built most of the closure, and that is the work a
  retry should not repeat.
- Every failure warns and exits 0. A cache that refuses uploads must not turn a
  green build red.
- Requires `jq` and a flake in `$GITHUB_WORKSPACE` (`--inputs-from .` resolves
  the attic client through your lock file rather than the mutable registry).
