#!/usr/bin/env bash
# PreToolUse hook: Check for secret patterns in file content being written
# Exit code 2 = block the tool call

set -Eeuo pipefail

file_path="${TOOL_INPUT_FILE_PATH:-${TOOL_INPUT_file_path:-}}"
[[ -z "${file_path}" ]] && exit 0

# Only skip the dedicated example env file that may intentionally reference
# placeholder token formats; scan all other files, including Markdown, for secrets.
basename="$(basename "${file_path}")"
case "${basename}" in
.env.example) exit 0 ;;
esac

# Get the content being written (new_string for Edit, content for Write)
content="${TOOL_INPUT_new_string:-${TOOL_INPUT_content:-}}"
[[ -z "${content}" ]] && exit 0

# Check for common secret patterns
if printf '%s\n' "${content}" | grep -qiE '(BEGIN ((RSA|EC|DSA|OPENSSH) )?PRIVATE KEY)'; then
  echo "BLOCKED: Content contains a private key" >&2
  exit 2
fi

if printf '%s\n' "${content}" | grep -qE 'ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{82}'; then
  echo "BLOCKED: Content contains a GitHub personal access token" >&2
  exit 2
fi

if printf '%s\n' "${content}" | grep -qE 'ghs_[A-Za-z0-9]{36}'; then
  echo "BLOCKED: Content contains a GitHub server-to-server token" >&2
  exit 2
fi
