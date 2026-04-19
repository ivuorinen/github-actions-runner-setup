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

  # Build curl args; -o captures body to file, -w prints HTTP code to stdout.
  # Omitting -f so we can surface GitHub's error .message on 4xx/5xx.
  local -a curl_args=(
    -sSL --connect-timeout 10 --max-time 30
    --retry 3 --retry-all-errors
    -X "${method}"
    -H 'Accept: application/vnd.github+json'
    -H "Authorization: Bearer ${token}"
    -H 'X-GitHub-Api-Version: 2022-11-28'
    -o "${response_file}"
    -w '%{http_code}'
  )

  if [[ -n "${data}" ]]; then
    curl_args+=(-H 'Content-Type: application/json' -d "${data}")
  fi

  http_code="$(curl "${curl_args[@]}" "${url}")" || {
    rm -f "${response_file}"
    fail "Network error calling ${method} ${url}"
  }

  response="$(cat "${response_file}")"
  rm -f "${response_file}"

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
  token="$(printf '%s' "${response}" | jq -r '.token // empty' 2>/dev/null || true)"
  if [[ -z "${token}" ]]; then
    local message
    message="$(printf '%s' "${response}" | jq -r '.message // empty' 2>/dev/null || true)"
    fail "API returned no token${message:+: ${message}}"
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

# Pre-computed remove token populated in main() so the PEM can be deleted
# before config.sh / run.sh starts, preventing workflow jobs from reading it.
RUNNER_REMOVE_TOKEN=""

deregister_runner() {
  local remove_token="${RUNNER_REMOVE_TOKEN}"
  if [[ -z "${remove_token}" ]]; then
    # Startup failed before we pre-computed the token.  Try to re-fetch via
    # PEM if it is still present (e.g. startup error before deletion).
    if [[ -f "/runner-tmp/github-app.pem" ]]; then
      local jwt installation_token
      jwt="$(make_jwt "${GITHUB_APP_ID}" "/runner-tmp/github-app.pem")"
      installation_token="$(get_installation_token "${jwt}")"
      remove_token="$(get_remove_token "${installation_token}")"
    else
      log 'Warning: no remove token and no PEM available; runner may need manual deregistration'
      return 0
    fi
  fi
  ./config.sh remove --unattended --token "${remove_token}"
}

cleanup() {
  local exit_code="$?"
  set +e

  if [[ -f ".runner" ]]; then
    log 'Removing runner registration'
    # Run in a subshell so that exit/fail inside deregister_runner cannot
    # abort the rest of cleanup (specifically: PEM deletion below).
    (deregister_runner) || log 'Warning: failed to deregister runner'
  fi

  rm -f /runner-tmp/github-app.pem
  exit "${exit_code}"
}

main() {
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  require_env GITHUB_APP_ID
  require_env GITHUB_APP_INSTALLATION_ID
  require_env GITHUB_APP_PRIVATE_KEY_FILE
  require_env RUNNER_SCOPE
  require_env RUNNER_WORKDIR

  # Default to the public GitHub endpoints when explicit values are not
  # provided (for example, when running outside docker-compose). GitHub
  # Enterprise Server users must override both variables for their instance.
  : "${GITHUB_API_URL:=https://api.github.com}"
  : "${GITHUB_WEB_URL:=https://github.com}"

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
  [[ -f "${GITHUB_APP_PRIVATE_KEY_FILE}" ]] ||
    fail "Key file not found: ${GITHUB_APP_PRIVATE_KEY_FILE}"
  [[ -r "${GITHUB_APP_PRIVATE_KEY_FILE}" ]] ||
    fail "Key file is not readable by the runner user (UID $(id -u)): ${GITHUB_APP_PRIVATE_KEY_FILE} — run: chown $(id -u) ${GITHUB_APP_PRIVATE_KEY_HOST_PATH:-<host-path>} on the Docker host"
  install -m 600 "${GITHUB_APP_PRIVATE_KEY_FILE}" /runner-tmp/github-app.pem

  local jwt installation_token registration_token target_url runner_name
  jwt="$(make_jwt "${GITHUB_APP_ID}" "/runner-tmp/github-app.pem")"
  installation_token="$(get_installation_token "${jwt}")"
  registration_token="$(get_registration_token "${installation_token}")"
  # Pre-compute the remove token while we have the installation token so we can
  # delete the PEM immediately — before config.sh / run.sh starts.  Workflow
  # jobs run as the same user that owns the PEM, so keeping it alive through the
  # entire run would allow any job to read the GitHub App private key and mint
  # new tokens.
  # The primary deregistration path for ephemeral runners is the GitHub Actions
  # service itself: when --ephemeral is passed to config.sh, the runner
  # automatically unregisters after completing one job.  The remove token /
  # config.sh remove call in cleanup() is a safety net for abnormal exits
  # (container killed before picking up a job, startup failure, SIGTERM).
  # Remove tokens expire after 1 hour — sufficient for the startup→job window
  # of an ephemeral runner.  Idle waits longer than 1 hour are not expected;
  # if they occur the fallback path in deregister_runner() will re-fetch a
  # fresh token from the PEM if it is still available.
  RUNNER_REMOVE_TOKEN="$(get_remove_token "${installation_token}")"
  rm -f /runner-tmp/github-app.pem
  log 'GitHub App PEM deleted — registration and remove tokens pre-computed'
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

  ./config.sh "${config_args[@]}"

  # Unset variables that are no longer needed after registration so they do not
  # leak into runner job subprocesses.  Variables required for cleanup/
  # deregistration are intentionally kept:
  #   - GITHUB_API_URL, RUNNER_SCOPE, GITHUB_ORG, GITHUB_REPO_*: used by
  #     get_remove_token() / api() during deregister_runner
  #   - GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID: used by the fallback path
  #     in deregister_runner when RUNNER_REMOVE_TOKEN is empty and the PEM
  #     is still present (early-startup-failure recovery)
  #   - RUNNER_REMOVE_TOKEN: the pre-computed remove token itself
  if [[ "${UNSET_CONFIG_VARS:-true}" == "true" ]]; then
    log 'Unsetting post-registration configuration variables'
    unset RUNNER_DEFAULT_LABELS RUNNER_EXTRA_LABELS RUNNER_LABELS RUNNER_GROUP
    unset RUNNER_INSTANCE_NAME RUNNER_WORKDIR GITHUB_WEB_URL
  fi

  log 'Starting runner listener'
  ./run.sh
}

main "$@"
