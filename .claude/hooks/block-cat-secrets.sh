#!/usr/bin/env bash
# PreToolUse hook: prevent shell commands that would dump secrets to stdout.
# Examples blocked:
#   cat .env
#   cat '.env'                       # single-quoted bypass
#   cat ".env"                       # double-quoted bypass
#   bash -c "cat .env"               # subshell wrapper bypass
#   cat /etc/github-app/private-key.pem
#   strings key.pem
#   env | tee out                    # bulk env dump without filter
#
# The hook also enforces that any `bash -c` / `sh -c` payload is itself
# scanned for the forbidden patterns (recursive check).
#
# Exit code 2 = block the tool call.

set -Eeuo pipefail

command="${TOOL_INPUT_command:-}"
[[ -z "${command}" ]] && exit 0

# Tools that print file contents to stdout. POSIX ERE (bash =~ does not
# support PCRE \b word boundaries).
readonly DUMP_TOOLS_RE='(^|[[:space:]])(cat|less|more|head|tail|bat|nl|tac|xxd|hexdump|od|strings)([[:space:]]|$)'

# Normalise the command string before pattern checks: strip single and double
# quotes wrapping individual tokens so `cat '.env'` and `cat ".env"` look the
# same as `cat .env`. We strip ALL ASCII quotes; this loses literal-quote
# semantics but the hook only cares about token presence, not execution.
normalise() {
  printf '%s' "$1" | tr -d "'\""
}

# Recursively expand `bash -c <payload>` / `sh -c <payload>` invocations so
# the payload is checked alongside the outer command. We do one level of
# expansion (an attacker chaining bash -c "bash -c ..." would still be
# caught by the outer check since the inner payload contains the forbidden
# token literal).
expand_subshells() {
  local cmd="$1"
  # Match `bash -c '...'` or `sh -c "..."` or `bash -c ...` (unquoted).
  # We just append the entire command again — any literal occurrence of
  # the forbidden token in the payload will be present in the outer string.
  printf '%s' "${cmd}"
}

scan_payload="$(expand_subshells "$(normalise "${command}")")"

# Split on shell separators so we examine each subcommand independently.
old_ifs="${IFS}"
IFS=$';|&\n'
# shellcheck disable=SC2206 # intentional word-splitting for shell separators
parts=(${scan_payload})
IFS="${old_ifs}"

# Helper: walk a single command segment looking for the forbidden combos.
inspect_segment() {
  local part="$1"
  [[ -z "${part}" ]] && return 0

  # Skip segments that do not invoke a dump tool.
  if ! [[ "${part}" =~ ${DUMP_TOOLS_RE} ]]; then
    return 0
  fi

  # Allow .env.example explicitly.
  if [[ "${part}" =~ (^|[[:space:]/])\.env\.example([[:space:]]|$) ]]; then
    return 0
  fi

  # Block any .env / .env.<name>.
  if [[ "${part}" =~ (^|[[:space:]/])\.env([[:space:]]|$) ]] ||
    [[ "${part}" =~ (^|[[:space:]/])\.env\.[a-zA-Z0-9_-]+([[:space:]]|$) ]]; then
    cat >&2 <<MSG
BLOCKED: Shell command would dump a .env file to stdout, which leaks
secrets into the chat transcript. Use \`.env.example\` for documentation.
Command segment: ${part}
MSG
    exit 2
  fi

  # Block any .pem.
  if [[ "${part}" =~ \.pem([[:space:]]|$) ]]; then
    cat >&2 <<MSG
BLOCKED: Shell command would dump a .pem file (GitHub App private key) to
stdout. The PEM is the most sensitive credential in this system.
Command segment: ${part}
MSG
    exit 2
  fi
}

for part in "${parts[@]}"; do
  inspect_segment "${part}"
done

# Block bulk env dumps to a file or pipe when no filter is present.
if [[ "${command}" =~ ^[[:space:]]*(printenv|env)([[:space:]]|$) ]] &&
  [[ "${command}" =~ (\>|\|[[:space:]]*tee) ]] &&
  ! [[ "${command}" =~ grep ]]; then
  cat >&2 <<MSG
BLOCKED: \`env\`/\`printenv\` piped to a file or another command may capture
GITHUB_APP_INSTALLATION_ID, RUNNER_REMOVE_TOKEN, etc. Filter first:
  printenv | grep -v -E '(TOKEN|KEY|SECRET|PASSWORD)' > out
Command: ${command}
MSG
  exit 2
fi
