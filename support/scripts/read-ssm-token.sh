#!/usr/bin/env bash
# Read one SecureString parameter from AWS SSM, for the SSM inputs of nix-setup,
# nix-cache-push and app-token.
#
#   read-ssm-token.sh ROLE_ARN REGION PARAMETER OUT_FILE
#
# With a ROLE_ARN, the job's GitHub OIDC token is exchanged for that role. With
# an empty ROLE_ARN, the runner's own AWS credentials are used (an EC2 runner's
# instance profile); a GitHub-hosted runner has none.
#
# Writes the value to OUT_FILE (mode 0600) and masks it in the job log one line
# at a time, so a multi-line value such as a private key stays masked.
# Exit 0: read. Exit 3: a ROLE_ARN was given but the job has no OIDC token (a
# fork's pull request, or a job without `permissions: id-token: write`); the
# caller decides which. Exit 1: any other failure, with the reason on stderr.
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

if [ -n "$role" ] && { [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; }; then
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

if [ -n "$role" ]; then
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
		--role-session-name "github-actions-${GITHUB_RUN_ID:-local}" \
		--web-identity-token "file://$work/jwt" \
		--duration-seconds 900 \
		--query Credentials --output json >"$work/creds"; then
		echo "could not assume $role (is this repository and ref in its trust policy?)" >&2
		exit 1
	fi
	AWS_ACCESS_KEY_ID="$(jq -r .AccessKeyId "$work/creds")"
	AWS_SECRET_ACCESS_KEY="$(jq -r .SecretAccessKey "$work/creds")"
	AWS_SESSION_TOKEN="$(jq -r .SessionToken "$work/creds")"
	echo "::add-mask::$AWS_SECRET_ACCESS_KEY"
	echo "::add-mask::$AWS_SESSION_TOKEN"
	export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
	source="$role"
else
	source="the runner's own AWS credentials"
fi

if ! value="$(aws ssm get-parameter --region "$region" --name "$parameter" --with-decryption \
	--query Parameter.Value --output text)"; then
	echo "could not read $parameter with $source" >&2
	exit 1
fi
if [ -z "$value" ] || [ "$value" = "CHANGE_ME" ]; then
	echo "$parameter still holds its Terraform placeholder; its real value has not been set yet" >&2
	exit 1
fi
# A mask covers one line: masking a multi-line value at once would leave every
# line after the first readable in the log.
while IFS= read -r line; do
	if [ -n "$line" ]; then echo "::add-mask::$line"; fi
done <<<"$value"

(
	umask 077
	printf '%s' "$value" >"$out"
)
