# Action reference

## nix-setup

Installs Nix (pinned installer, pinned `install-nix-action` commit) and writes
`nix.conf` with our substituters, trusted keys, and cache credentials.

| Input                            | Default                             | Description                                                                                                     |
| -------------------------------- | ----------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `github_token`                   | —                                   | authenticates GitHub flake inputs; they are rate-limited without one                                            |
| `cache_pull_token`               | `""`                                | pull token for the GenLayer cache; empty warns and relies on the runner's own netrc, if any                     |
| `cache_pull_token_ssm_parameter` | `""`                                | SSM parameter holding the pull token, read in-job with `aws_role_arn`; set this or `cache_pull_token`, not both |
| `aws_role_arn`                   | `""`                                | role the job assumes with its OIDC token to read the SSM parameter; needs `id-token: write`                     |
| `aws_region`                     | `us-east-1`                         | region of the SSM parameter                                                                                     |
| `enable_genlayerlabs_cache`      | `true`                              | set `false` to measure a cold build, or to avoid paths a bad push may have poisoned                             |
| `cache_url`                      | `https://nix-cache.ygr.ai/genlayer` | substituter URL                                                                                                 |
| `cache_public_key`               | `genlayer:hMvP8Bk…`                 | trusted public key                                                                                              |
| `extra_substituters`             | `""`                                | whitespace-separated; each needs its key below                                                                  |
| `extra_trusted_public_keys`      | `""`                                | whitespace-separated                                                                                            |
| `extra_nix_config`               | `""`                                | lines appended verbatim to `nix.conf`; later lines win                                                          |

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
- With `cache_pull_token_ssm_parameter`, the token comes from SSM through
  `support/scripts/read-ssm-token.sh`: the job's GitHub OIDC token is exchanged
  for `aws_role_arn` (devexp-tf-infra, `github-oidc-<repo>-nix-cache-tokens`)
  and the parameter is read and masked. The cache host rotates it
  (devexp-nix-cache, `ciTokens`), so it does not expire unnoticed. A failed
  read warns and builds from source, like a bad token. A job without an OIDC
  token fails, because it lacks `permissions: id-token: write`, unless it is a
  fork's pull request, which never gets one and only warns. Needs the `aws`
  CLI, `curl` and `jq` on the runner (GitHub-hosted runners have all three).

## nix-cache-push

Uploads paths this job built locally.

| Input                 | Default                    | Description                                                                                          |
| --------------------- | -------------------------- | ---------------------------------------------------------------------------------------------------- |
| `token`               | `""`                       | push token; empty skips the step entirely                                                            |
| `token_ssm_parameter` | `""`                       | SSM parameter holding the push token, read in-job with `aws_role_arn`; set this or `token`, not both |
| `aws_role_arn`        | `""`                       | role the job assumes with its OIDC token to read the SSM parameter; needs `id-token: write`          |
| `aws_region`          | `us-east-1`                | region of the SSM parameter                                                                          |
| `cache`               | `genlayer`                 | cache name on the server                                                                             |
| `endpoint`            | `https://nix-cache.ygr.ai` | attic server                                                                                         |
| `include`             | `genlayer\|genvm`          | regex on the store path name, hash stripped                                                          |
| `exclude`             | `""`                       | regex on the full store path; empty disables                                                         |
| `verify`              | `"false"`                  | `"true"` fails the job unless every pushed path is in the cache afterwards                           |

Notes:

- Selects paths by Nix's `ultimate` flag — "built on this machine" — which is
  exactly the set worth uploading. Anything else came from a substituter that
  already has it.
- Guard the step with `if: ${{ !cancelled() }}`, not the default `success()`. A
  job that failed late still built most of the closure, and that is the work a
  retry should not repeat.
- By default every failure warns and exits 0. A cache that refuses uploads must
  not turn a green build red.
- `verify: "true"` is the opt-in exception, for a job whose output consumers
  depend on (a release, the build that warms a branch head). A failed client
  build, path listing, login or upload exits 1, and each pushed path is then
  read back (`<endpoint>/<cache>/<hash>.narinfo` with the push token, which can
  pull): any answer but 200 fails the job and names the path and the HTTP code.
  This is what makes an expired push token visible — without it a refused push
  is only a warning in a green job. It needs `curl`.
- `token_ssm_parameter` reads the push token from SSM the same way as
  `nix-setup`'s `cache_pull_token_ssm_parameter`. A failed read is a failed
  upload: a warning, or an error with `verify`. A fork's pull request skips the
  step; any other job without an OIDC token fails.
- Requires `jq` and a flake in `$GITHUB_WORKSPACE` (`--inputs-from .` resolves
  the attic client through your lock file rather than the mutable registry).
