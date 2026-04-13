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
  token="$(printf '%s' "${response}" | jq -r '.token')"
  if [[ -z "${token}" || "${token}" == "null" ]]; then
    local message
    message="$(printf '%s' "${response}" | jq -r '.message // empty')"
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

cleanup() {
  local exit_code="$?"
  set +e

  if [[ -f ".runner" ]]; then
    log 'Removing runner registration'
    (
      jwt="$(make_jwt "${GITHUB_APP_ID}" "/runner-tmp/github-app.pem")"
      installation_token="$(get_installation_token "${jwt}")"
      remove_token="$(get_remove_token "${installation_token}")"
      ./config.sh remove --unattended --token "${remove_token}"
    ) || log 'Warning: failed to deregister runner'
  fi

  rm -f /runner-tmp/github-app.pem
  exit "${exit_code}"
}

main() {
  trap cleanup EXIT INT TERM

  require_env GITHUB_APP_ID
  require_env GITHUB_APP_INSTALLATION_ID
  # Require exactly one of: a pre-mounted key file (preferred, not stored in
  # container env/config) or a base64-encoded key in the environment.
  if [[ -z "${GITHUB_APP_PRIVATE_KEY_FILE:-}" && -z "${GITHUB_APP_PRIVATE_KEY_B64:-}" ]]; then
    fail "Either GITHUB_APP_PRIVATE_KEY_FILE or GITHUB_APP_PRIVATE_KEY_B64 must be set"
  fi
  require_env RUNNER_SCOPE
  require_env RUNNER_LABELS
  require_env RUNNER_WORKDIR

  if [[ "${RUNNER_SCOPE}" == "org" ]]; then
    require_env GITHUB_ORG
  elif [[ "${RUNNER_SCOPE}" == "repo" ]]; then
    require_env GITHUB_REPO_OWNER
    require_env GITHUB_REPO_NAME
  fi

  umask 077
  # Populate /runner-tmp/github-app.pem from whichever source is configured.
  # GITHUB_APP_PRIVATE_KEY_FILE (a mounted file) is preferred because it avoids
  # storing the secret in the container's environment/config (visible via
  # `docker inspect`). GITHUB_APP_PRIVATE_KEY_B64 is supported as a fallback for
  # environments that inject secrets only through environment variables (e.g. Coolify).
  if [[ -n "${GITHUB_APP_PRIVATE_KEY_FILE:-}" ]]; then
    [[ -f "${GITHUB_APP_PRIVATE_KEY_FILE}" ]] \
      || fail "Key file not found: ${GITHUB_APP_PRIVATE_KEY_FILE}"
    install -m 600 "${GITHUB_APP_PRIVATE_KEY_FILE}" /runner-tmp/github-app.pem
  else
    printf '%s' "${GITHUB_APP_PRIVATE_KEY_B64}" | base64 -d >/runner-tmp/github-app.pem
    unset GITHUB_APP_PRIVATE_KEY_B64
  fi

  local jwt installation_token registration_token target_url runner_name
  jwt="$(make_jwt "${GITHUB_APP_ID}" "/runner-tmp/github-app.pem")"
  installation_token="$(get_installation_token "${jwt}")"
  registration_token="$(get_registration_token "${installation_token}")"
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

  log 'Starting runner listener'
  ./run.sh
}

main "$@"
