#!/usr/bin/env bash
# Read one SecureString parameter from AWS SSM with the job's GitHub OIDC token,
# for the SSM inputs of nix-setup and nix-cache-push.
#
#   read-ssm-token.sh ROLE_ARN REGION PARAMETER OUT_FILE
#
# Writes the value to OUT_FILE (mode 0600) and masks it in the job log.
# Exit 0: read. Exit 3: the job has no OIDC token (a fork's pull request, or a
# job without `permissions: id-token: write`); the caller decides which. Exit 1:
# any other failure, with the reason on stderr.
#
# No `set -x`: the OIDC token, the role credentials and the value all pass
# through this script. None of them reaches argv, which any user can read.
set -euo pipefail

if [ "$#" -ne 4 ]; then
	echo "usage: read-ssm-token.sh ROLE_ARN REGION PARAMETER OUT_FILE" >&2
	exit 1
fi
role=$1
region=$2
parameter=$3
out=$4

if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
	exit 3
fi

for tool in aws curl jq; do
	if ! command -v "$tool" >/dev/null; then
		echo "$tool is not installed on this runner" >&2
		exit 1
	fi
done

work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/ssm-token.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# The request token reaches curl through a config on stdin.
if ! printf 'header = "Authorization: bearer %s"\n' "$ACTIONS_ID_TOKEN_REQUEST_TOKEN" |
	curl -sSf -K - "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" |
	jq -er .value >"$work/jwt"; then
	echo "could not get an OIDC token from GitHub" >&2
	exit 1
fi
echo "::add-mask::$(cat "$work/jwt")"

if ! aws sts assume-role-with-web-identity \
	--region "$region" \
	--role-arn "$role" \
	--role-session-name "nix-cache-${GITHUB_RUN_ID:-local}" \
	--web-identity-token "file://$work/jwt" \
	--duration-seconds 900 \
	--query Credentials --output json >"$work/creds"; then
	echo "could not assume $role (is this repository and ref in its trust policy?)" >&2
	exit 1
fi
key_id="$(jq -r .AccessKeyId "$work/creds")"
secret="$(jq -r .SecretAccessKey "$work/creds")"
session="$(jq -r .SessionToken "$work/creds")"
echo "::add-mask::$secret"
echo "::add-mask::$session"

if ! value="$(AWS_ACCESS_KEY_ID="$key_id" AWS_SECRET_ACCESS_KEY="$secret" AWS_SESSION_TOKEN="$session" \
	aws ssm get-parameter --region "$region" --name "$parameter" --with-decryption \
	--query Parameter.Value --output text)"; then
	echo "could not read $parameter with $role" >&2
	exit 1
fi
if [ -z "$value" ] || [ "$value" = "CHANGE_ME" ]; then
	echo "$parameter still holds its Terraform placeholder; the cache host has not minted it yet" >&2
	exit 1
fi
echo "::add-mask::$value"

(
	umask 077
	printf '%s' "$value" >"$out"
)
