#!/usr/bin/env bash
# PreToolUse hook: prevent shell commands that would dump .env / .pem
# secrets into the chat transcript.
# Examples blocked:
#   cat .env
#   cat '.env'                       # single-quoted bypass
#   cat ".env"                       # double-quoted bypass
#   bash -c "cat .env"               # subshell wrapper bypass
#   awk '{print}' .env               # alternate-tool bypass
#   sed -n p .env
#   grep . .env
#   xxd .env / hexdump .env / od -c .env / strings .env
#   base64 .env
#   tar c .env                       # tarball-of-one bypass
#   cat /etc/github-app/private-key.pem
#   x=$(< .env); printf '%s' "$x"    # shell $(<file) bypass
#   while read l; do echo "$l"; done < .env
#   env | tee out                    # bulk env dump without filter
#
# The hook also enforces that any `bash -c` / `sh -c` payload is itself
# scanned for the forbidden patterns (recursive check). The dump-tool list
# is intentionally generous; bypass is not the goal, accident-prevention is.
#
# Exit code 2 = block the tool call.

set -Eeuo pipefail

command="${TOOL_INPUT_command:-}"
[[ -z "${command}" ]] && exit 0

# Tools that print / dump file contents. POSIX ERE (bash =~ does not
# support PCRE \b word boundaries) — we use explicit start-of-token guards.
readonly DUMP_TOOLS_RE='(^|[[:space:]])(cat|less|more|head|tail|bat|nl|tac|xxd|hexdump|od|strings|base64|awk|sed|grep|rg|ag|fgrep|egrep|tar|dd|cp|mv|install)([[:space:]]|$)'

# Normalise the command: strip ASCII single and double quotes so quoted
# token forms (`cat '.env'`, `cat ".env"`) look the same as the bare form.
normalise() {
  printf '%s' "$1" | tr -d "'\""
}

scan_payload="$(normalise "${command}")"

# Split on shell separators so we examine each subcommand independently.
old_ifs="${IFS}"
IFS=$';|&\n'
# shellcheck disable=SC2206 # intentional word-splitting for shell separators
parts=(${scan_payload})
IFS="${old_ifs}"

is_env_target() {
  # Match `.env` or `.env.<suffix>` as a token, but NOT `.env.example`.
  local part="$1"
  if [[ "${part}" =~ (^|[[:space:]/<])\.env\.example([[:space:]]|$) ]]; then
    return 1
  fi
  if [[ "${part}" =~ (^|[[:space:]/<])\.env([[:space:]]|$) ]] ||
    [[ "${part}" =~ (^|[[:space:]/<])\.env\.[a-zA-Z0-9_-]+([[:space:]]|$) ]]; then
    return 0
  fi
  return 1
}

is_pem_target() {
  local part="$1"
  # Match the conventional `*.pem` suffix AND the container-side mount
  # path that the entrypoint reads (GITHUB_APP_PRIVATE_KEY_FILE defaults
  # to /run/secrets/github_app_key inside the runner container, which is
  # the load-bearing path; also catch anything under /run/secrets/ since
  # that path is reserved for sensitive bind-mounted material).
  [[ "${part}" =~ \.pem([[:space:]]|$) ]] ||
    [[ "${part}" =~ (^|[[:space:]/])/run/secrets/[A-Za-z0-9._-]+ ]] ||
    [[ "${part}" =~ (^|[[:space:]/])github_app_key([[:space:]]|$) ]] ||
    [[ "${part}" =~ private-key([[:space:]]|$|\.) ]]
}

inspect_segment() {
  local part="$1"
  [[ -z "${part}" ]] && return 0

  # Catch `read … < .env`, `done < .env`, and similar redirect-form leaks.
  if [[ "${part}" =~ \<[[:space:]]*\.env([[:space:]]|$|\.[a-zA-Z0-9_-]+) ]] &&
    ! [[ "${part}" =~ \<[[:space:]]*\.env\.example([[:space:]]|$) ]]; then
    cat >&2 <<MSG
BLOCKED: Shell command would read a .env file via a < redirect, which
leaks secrets into the chat transcript. Use \`.env.example\` for documentation.
Command segment: ${part}
MSG
    exit 2
  fi

  # Catch \$(< .env) shell substitution.
  if [[ "${part}" =~ \\?\$\([[:space:]]*\<[[:space:]]*\.env([[:space:]]|\.[a-zA-Z0-9_-]+|\)) ]]; then
    cat >&2 <<MSG
BLOCKED: Shell command would read a .env file via \$(< file) substitution.
Command segment: ${part}
MSG
    exit 2
  fi

  # Skip segments that do not invoke a dump tool.
  if ! [[ "${part}" =~ ${DUMP_TOOLS_RE} ]]; then
    return 0
  fi

  if is_env_target "${part}"; then
    cat >&2 <<MSG
BLOCKED: Shell command would dump a .env file to stdout, which leaks
secrets into the chat transcript. Use \`.env.example\` for documentation.
Command segment: ${part}
MSG
    exit 2
  fi

  if is_pem_target "${part}"; then
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
