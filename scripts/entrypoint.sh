#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[entrypoint] %s\n' "$*"
}

fail() {
  printf '[entrypoint] ERROR: %s\n' "$*" >&2
  exit 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "Required environment variable is missing: ${name}"
  fi
}

base64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

make_jwt() {
  local app_id="$1"
  local pem_file="$2"
  local now iat exp header payload unsigned signature

  now="$(date +%s)"
  iat="$((now - 60))"
  exp="$((iat + 540))"

  header='{"alg":"RS256","typ":"JWT"}'
  payload="{\"iat\":${iat},\"exp\":${exp},\"iss\":${app_id}}"

  unsigned="$(printf '%s' "${header}" | base64url).$(printf '%s' "${payload}" | base64url)"
  signature="$(printf '%s' "${unsigned}" | openssl dgst -binary -sha256 -sign "${pem_file}" | base64url)"

  printf '%s.%s' "${unsigned}" "${signature}"
}

api() {
  local method="$1"
  local url="$2"
  local token="$3"
  local data="${4:-}"
  local response_file http_code response message

  response_file="$(mktemp)"
  # Ensure the tempfile is removed even if a signal interrupts api() between
  # mktemp and the explicit rm below. The file is mode 600 on tmpfs but
  # cleaning up proactively keeps /tmp tidy and removes any short-lived
  # token-bearing response body. RETURN trap fires when this function exits.
  # shellcheck disable=SC2064 # intentionally expand response_file now
  trap "rm -f '${response_file}'" RETURN

  # Build curl args; -o captures body to file, -w prints HTTP code to stdout.
  # Omitting -f so we can surface GitHub's error .message on 4xx/5xx.
  #
  # Timeouts:
  #   --connect-timeout 10  — give TLS handshake a chance over slow links
  #   --max-time 60         — per-attempt cap (not total); 3 retries × 60s
  #                           gives a 3-minute worst case for token endpoints
  #
  # Retries:
  #   --retry 3              — 3 retries on top of the first attempt.
  #                            curl's default --retry covers transient
  #                            errors (5xx, connection failures, timeouts).
  #                            We intentionally do NOT pass --retry-all-errors:
  #                            it would also retry on 401/403/404, which are
  #                            authentication / permission / installation
  #                            misconfiguration — wasteful and obscures the
  #                            real error. 429 (rate limit) is rare for
  #                            runner registration and the operator can
  #                            re-deploy if hit. The exponential backoff
  #                            (curl default: 1s, 2s, 4s, …) applies.
  #
  # API version 2022-11-28 is the long-term GA version; 2026-03-10 is the
  # newer default in the docs but offers nothing we need. Keep 2022-11-28
  # until a feature requires the newer version.
  local -a curl_args=(
    -sS --location
    --connect-timeout 10 --max-time 60
    --retry 3
    -X "${method}"
    -H 'Accept: application/vnd.github+json'
    -H "Authorization: Bearer ${token}"
    -H 'X-GitHub-Api-Version: 2022-11-28'
    -H "User-Agent: ivuorinen/github-actions-runner-setup"
    -o "${response_file}"
    -w '%{http_code}'
  )

  if [[ -n "${data}" ]]; then
    curl_args+=(-H 'Content-Type: application/json' -d "${data}")
  fi

  http_code="$(curl "${curl_args[@]}" "${url}")" || {
    fail "Network error calling ${method} ${url}"
  }

  response="$(cat "${response_file}")"
  # response_file removed by the RETURN trap above

  if [[ ! "${http_code}" =~ ^2[0-9][0-9]$ ]]; then
    message="$(printf '%s' "${response}" | jq -r '.message // ""' 2>/dev/null || true)"
    fail "API ${method} ${url} returned HTTP ${http_code}${message:+: ${message}}"
  fi

  printf '%s' "${response}"
}

extract_token() {
  local response="$1"
  local token
  # Use '// empty' so jq converts null → "", and suppress parse errors with
  # || true so that a non-JSON/empty response falls through to the fail below
  # instead of aborting with an opaque jq error under set -Eeuo pipefail.
  # Note: jq's `// empty` does NOT trigger for the empty string "" (only for
  # null/absent), so we additionally test [[ -z ]] below to reject an empty
  # token value that GitHub *technically* could return.
  token="$(printf '%s' "${response}" | jq -r '.token // empty' 2>/dev/null || true)"
  if [[ -z "${token}" ]]; then
    local message
    message="$(printf '%s' "${response}" | jq -r '.message // empty' 2>/dev/null || true)"
    fail "API returned no token${message:+: ${message}}"
  fi
  # Defense in depth: a real installation / registration token is dozens of
  # characters (alphanumeric with underscores and dashes). We reject anything
  # shorter than 10 as a parse error (e.g. a 1-char value from the wrong JSON
  # field) without asserting an exact length, since GitHub does not document a
  # guaranteed minimum.
  if [[ "${#token}" -lt 10 ]]; then
    fail "API returned a suspiciously short token (length ${#token}); refusing to use it"
  fi
  printf '%s' "${token}"
}

get_installation_token() {
  local jwt="$1"
  local url="${GITHUB_API_URL}/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens"
  local response
  response="$(api POST "${url}" "${jwt}" '{}')"
  extract_token "${response}"
}

get_registration_token() {
  local installation_token="$1"
  local url

  if [[ "${RUNNER_SCOPE}" == "org" ]]; then
    require_env GITHUB_ORG
    url="${GITHUB_API_URL}/orgs/${GITHUB_ORG}/actions/runners/registration-token"
  elif [[ "${RUNNER_SCOPE}" == "repo" ]]; then
    require_env GITHUB_REPO_OWNER
    require_env GITHUB_REPO_NAME
    url="${GITHUB_API_URL}/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/actions/runners/registration-token"
  else
    fail "RUNNER_SCOPE must be either org or repo"
  fi

  local response
  response="$(api POST "${url}" "${installation_token}" '{}')"
  extract_token "${response}"
}

get_remove_token() {
  local installation_token="$1"
  local url

  if [[ "${RUNNER_SCOPE}" == "org" ]]; then
    url="${GITHUB_API_URL}/orgs/${GITHUB_ORG}/actions/runners/remove-token"
  else
    url="${GITHUB_API_URL}/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/actions/runners/remove-token"
  fi

  local response
  response="$(api POST "${url}" "${installation_token}" '{}')"
  extract_token "${response}"
}

runner_url() {
  if [[ "${RUNNER_SCOPE}" == "org" ]]; then
    printf '%s/%s' "${GITHUB_WEB_URL}" "${GITHUB_ORG}"
  else
    printf '%s/%s/%s' "${GITHUB_WEB_URL}" "${GITHUB_REPO_OWNER}" "${GITHUB_REPO_NAME}"
  fi
}

# Pre-computed remove token populated in main() so cleanup does not need to
# re-sign a JWT on shutdown.  If population fails (e.g. startup error before
# main() reaches that point), deregister_runner falls back to re-fetching
# from the still-mounted PEM.
RUNNER_REMOVE_TOKEN=""

deregister_runner() {
  local remove_token="${RUNNER_REMOVE_TOKEN}"
  if [[ -z "${remove_token}" ]]; then
    if [[ -n "${GITHUB_APP_PRIVATE_KEY_FILE:-}" && -r "${GITHUB_APP_PRIVATE_KEY_FILE}" ]]; then
      local jwt installation_token
      jwt="$(make_jwt "${GITHUB_APP_ID}" "${GITHUB_APP_PRIVATE_KEY_FILE}")"
      installation_token="$(get_installation_token "${jwt}")"
      remove_token="$(get_remove_token "${installation_token}")"
    else
      log 'Warning: no remove token and no readable PEM available; runner may need manual deregistration'
      return 0
    fi
  fi
  # Runs as the runner user for the same reasons as the registration call:
  # config.sh expects to operate against a runner-owned .runner state file.
  gosu runner ./config.sh remove --unattended --token "${remove_token}"
}

cleanup() {
  local exit_code="$?"
  set +e

  if [[ -f ".runner" ]]; then
    log 'Removing runner registration'
    # Run in a subshell so that exit/fail inside deregister_runner cannot
    # abort the rest of cleanup.
    (deregister_runner) || log 'Warning: failed to deregister runner'
  fi

  # Wipe the in-memory token regardless of cleanup outcome. The shell
  # exits immediately after but a defensive unset closes the window
  # where a debugger attached at exit could read process memory.
  RUNNER_REMOVE_TOKEN=""
  unset RUNNER_REMOVE_TOKEN

  exit "${exit_code}"
}

runner_pid=""
# Holds the most recent signal name received before runner_pid was set, so a
# SIGTERM arriving during the tiny window between `./run.sh &` and the
# `runner_pid=$!` assignment is not lost. main() consults this flag right
# after capturing the PID and forwards any pending signal immediately.
pending_signal=""

_forward_to_runner() {
  local sig="$1"
  if [[ -n "${runner_pid}" ]]; then
    log "Received SIG${sig}, forwarding to runner listener (PID ${runner_pid}) for graceful shutdown"
    kill -"${sig}" "${runner_pid}" 2>/dev/null || true
  else
    # PID not set yet — remember and replay once main() assigns runner_pid.
    pending_signal="${sig}"
    log "Received SIG${sig} before runner listener was started; queued for replay"
  fi
}

main() {
  trap cleanup EXIT
  # Forward TERM/INT to the runner listener so it can finish the current job
  # and deregister cleanly before the EXIT trap runs cleanup().  Without
  # forwarding, the parent bash would exit immediately on signal and
  # config.sh remove in cleanup() could race a still-running Runner.Listener.
  trap '_forward_to_runner TERM' TERM
  trap '_forward_to_runner INT' INT

  require_env GITHUB_APP_ID
  require_env GITHUB_APP_INSTALLATION_ID
  require_env GITHUB_APP_PRIVATE_KEY_FILE
  require_env RUNNER_SCOPE
  require_env RUNNER_WORKDIR

  # Default to the public GitHub endpoints when explicit values are not
  # provided (for example, when running outside docker-compose). For GHES,
  # operators can either:
  #   1. set GITHUB_API_URL and GITHUB_WEB_URL directly (most explicit), OR
  #   2. set only GITHUB_HOST=ghes.example.com and let entrypoint derive
  #      the API URL (https://<host>/api/v3) and web URL (https://<host>).
  # Explicit values take precedence over GITHUB_HOST-derived ones.
  if [[ -n "${GITHUB_HOST:-}" && "${GITHUB_HOST}" != "github.com" ]]; then
    : "${GITHUB_API_URL:=https://${GITHUB_HOST}/api/v3}"
    : "${GITHUB_WEB_URL:=https://${GITHUB_HOST}}"
  else
    : "${GITHUB_API_URL:=https://api.github.com}"
    : "${GITHUB_WEB_URL:=https://github.com}"
  fi
  # Strip any trailing slash so request URLs do not end up with `//` in the
  # path (which github.com forgives but some GHES versions return 404 on).
  GITHUB_API_URL="${GITHUB_API_URL%/}"
  GITHUB_WEB_URL="${GITHUB_WEB_URL%/}"

  # Disable core dumps so that a runner crash with the JWT, installation
  # token, or remove token in memory cannot leak credential bytes to disk
  # via a core file. tmpfs would discard them at container exit anyway,
  # but explicit `ulimit -c 0` avoids the window between crash and exit.
  ulimit -c 0

  # Build the runner label set from default and per-runner extra labels,
  # assembling here rather than in docker-compose.yml so that an empty
  # RUNNER_EXTRA_LABELS never produces a trailing comma.
  # Falls back to a pre-built RUNNER_LABELS for direct `docker run -e` usage.
  if [[ -z "${RUNNER_LABELS:-}" ]]; then
    if [[ -n "${RUNNER_EXTRA_LABELS:-}" ]]; then
      RUNNER_LABELS="${RUNNER_DEFAULT_LABELS:-self-hosted,linux,x64,docker,ephemeral},${RUNNER_EXTRA_LABELS}"
    else
      RUNNER_LABELS="${RUNNER_DEFAULT_LABELS:-self-hosted,linux,x64,docker,ephemeral}"
    fi
  fi
  [[ -n "${RUNNER_LABELS}" ]] || fail "RUNNER_LABELS is empty — set RUNNER_DEFAULT_LABELS or RUNNER_EXTRA_LABELS"

  if [[ "${RUNNER_SCOPE}" == "org" ]]; then
    require_env GITHUB_ORG
  elif [[ "${RUNNER_SCOPE}" == "repo" ]]; then
    require_env GITHUB_REPO_OWNER
    require_env GITHUB_REPO_NAME
  else
    fail "RUNNER_SCOPE must be 'org' or 'repo', got: ${RUNNER_SCOPE}"
  fi

  umask 077
  # Entrypoint must run as root so the PEM can be owned by UID 0 (unreadable
  # by the runner user). After token exchange, main() drops privileges to
  # the runner user via gosu before exec'ing config.sh and run.sh.
  [[ "$(id -u)" -eq 0 ]] ||
    fail "entrypoint.sh must run as root (UID 0), got UID $(id -u) — do not set 'user:' in docker-compose.yml"

  [[ -f "${GITHUB_APP_PRIVATE_KEY_FILE}" ]] ||
    fail "Key file not found: ${GITHUB_APP_PRIVATE_KEY_FILE}"
  [[ -r "${GITHUB_APP_PRIVATE_KEY_FILE}" ]] ||
    fail "Key file is not readable by root: ${GITHUB_APP_PRIVATE_KEY_FILE} — on the Docker host run: chown 0:0 <pem> && chmod 600 <pem>"

  local key_owner key_mode
  key_owner="$(stat -c '%u' "${GITHUB_APP_PRIVATE_KEY_FILE}")"
  [[ "${key_owner}" == "0" ]] ||
    fail "Key file must be owned by UID 0 (root) inside the container so the runner user cannot read it; got UID ${key_owner}. On the Docker host run: chown 0:0 ${GITHUB_APP_PRIVATE_KEY_FILE}"

  key_mode="$(stat -c '%a' "${GITHUB_APP_PRIVATE_KEY_FILE}")"
  # NOTE: parentheses around `((8#${key_mode}) & 077)` are load-bearing.
  # Bash arithmetic gives `==` higher precedence than `&`, so the natural-
  # looking expression `(8#mode) & 077 == 0` parses as `key & (077 == 0)` =
  # `key & 0` = `0`, which would make the check always fail. Keep the inner
  # parens. See .claude/rules/09-arithmetic-precedence-bash.md
  ((((8#${key_mode}) & 077) == 0)) ||
    fail "Key file permissions must not grant any access to group or other users; got mode ${key_mode} on ${GITHUB_APP_PRIVATE_KEY_FILE}. On the Docker host run: chmod 600 \${GITHUB_APP_PRIVATE_KEY_HOST_PATH}"

  local jwt installation_token registration_token target_url runner_name
  jwt="$(make_jwt "${GITHUB_APP_ID}" "${GITHUB_APP_PRIVATE_KEY_FILE}")"
  installation_token="$(get_installation_token "${jwt}")"
  registration_token="$(get_registration_token "${installation_token}")"
  # Pre-compute the remove token while we still hold the installation token
  # so cleanup does not need to re-sign a fresh JWT on shutdown.
  # The primary deregistration path for ephemeral runners is the GitHub Actions
  # service itself: when --ephemeral is passed to config.sh, the runner
  # automatically unregisters after completing one job.  The remove token /
  # config.sh remove call in cleanup() is a safety net for abnormal exits
  # (container killed before picking up a job, startup failure, SIGTERM).
  # Remove tokens expire after 1 hour — sufficient for the startup→job window
  # of an ephemeral runner.  If the wait exceeds that, deregister_runner()
  # re-fetches a fresh token from the still-mounted PEM.
  # Non-fatal (N-76): deregister_runner() re-mints from the still-mounted PEM,
  # so a transient failure here must not block the runner from starting.
  RUNNER_REMOVE_TOKEN="$(get_remove_token "${installation_token}")" || {
    log 'Warning: could not pre-fetch remove token; will re-mint from PEM at cleanup if needed'
    RUNNER_REMOVE_TOKEN=""
  }
  target_url="$(runner_url)"

  if [[ -n "${RUNNER_INSTANCE_NAME:-}" ]]; then
    runner_name="${RUNNER_INSTANCE_NAME}"
  else
    runner_name="$(hostname)-$(date +%s)"
  fi

  log "Configuring runner ${runner_name} for ${target_url}"

  local -a config_args=(
    --unattended
    --replace
    --ephemeral
    --disableupdate
    --url "${target_url}"
    --token "${registration_token}"
    --name "${runner_name}"
    --labels "${RUNNER_LABELS}"
    --work "${RUNNER_WORKDIR}"
  )

  if [[ -n "${RUNNER_GROUP:-}" && "${RUNNER_SCOPE}" == "org" ]]; then
    log "Runner group: ${RUNNER_GROUP}"
    config_args+=(--runnergroup "${RUNNER_GROUP}")
  fi

  # config.sh is invoked as the runner user: (a) upstream expects non-root,
  # (b) the .runner state file and runner work dir need runner ownership,
  # (c) keeps the root bash process (which holds RUNNER_REMOVE_TOKEN in
  # memory) isolated from the registration subprocess.
  gosu runner ./config.sh "${config_args[@]}"

  # Unset variables that are no longer needed after registration so they do
  # not leak into runner job subprocesses. Variables required for cleanup/
  # deregistration are intentionally kept:
  #   - GITHUB_API_URL, RUNNER_SCOPE, GITHUB_ORG, GITHUB_REPO_*: used by
  #     get_remove_token() / api() during deregister_runner
  #   - GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID: used by the fallback path
  #     in deregister_runner when RUNNER_REMOVE_TOKEN is empty and the PEM
  #     is still present (early-startup-failure recovery)
  #   - RUNNER_REMOVE_TOKEN: non-exported shell variable, lives in bash
  #     memory only (not in child env)
  if [[ "${UNSET_CONFIG_VARS:-true}" == "true" ]]; then
    log 'Unsetting post-registration configuration variables'
    unset RUNNER_DEFAULT_LABELS RUNNER_EXTRA_LABELS RUNNER_LABELS RUNNER_GROUP
    unset RUNNER_INSTANCE_NAME RUNNER_WORKDIR GITHUB_WEB_URL
  fi

  # Run the listener as the runner user in the background so the parent
  # bash can intercept SIGTERM/SIGINT (via _forward_to_runner) and pass
  # them to the listener for a graceful shutdown before cleanup() runs
  # deregister_runner.  The root bash process stays as parent so the
  # EXIT trap can deregister with the pre-computed remove token.
  log 'Starting runner listener'
  gosu runner ./run.sh &
  runner_pid=$!

  # If a SIGTERM/SIGINT arrived during the background-launch window before
  # runner_pid was assigned, _forward_to_runner queued it. Replay it now so
  # the listener gets a chance to drain instead of being SIGKILL'd at the
  # end of stop_grace_period.
  if [[ -n "${pending_signal}" ]]; then
    log "Replaying queued SIG${pending_signal} to runner listener (PID ${runner_pid})"
    kill -"${pending_signal}" "${runner_pid}" 2>/dev/null || true
    pending_signal=""
  fi

  # A trap firing during 'wait' returns early with status 128+sig even
  # though the child is still running, so loop until the child PID is
  # actually gone.
  while kill -0 "${runner_pid}" 2>/dev/null; do
    wait "${runner_pid}" 2>/dev/null || true
  done
}

main "$@"
