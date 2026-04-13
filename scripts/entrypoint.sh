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
  local now exp header payload unsigned signature

  now="$(date +%s)"
  exp="$((now + 540))"

  header='{"alg":"RS256","typ":"JWT"}'
  payload="{\"iat\":${now},\"exp\":${exp},\"iss\":${app_id}}"

  unsigned="$(printf '%s' "${header}" | base64url).$(printf '%s' "${payload}" | base64url)"
  signature="$(printf '%s' "${unsigned}" | openssl dgst -binary -sha256 -sign "${pem_file}" | base64url)"

  printf '%s.%s' "${unsigned}" "${signature}"
}

api() {
  local method="$1"
  local url="$2"
  local token="$3"
  local data="${4:-}"

  if [[ -n "${data}" ]]; then
    curl -fsSL -X "${method}" \
      -H 'Accept: application/vnd.github+json' \
      -H "Authorization: Bearer ${token}" \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      -H 'Content-Type: application/json' \
      "${url}" \
      -d "${data}"
  else
    curl -fsSL -X "${method}" \
      -H 'Accept: application/vnd.github+json' \
      -H "Authorization: Bearer ${token}" \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      "${url}"
  fi
}

get_installation_token() {
  local jwt="$1"
  local url="${GITHUB_API_URL}/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens"
  api POST "${url}" "${jwt}" '{}' | jq -r '.token'
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

  api POST "${url}" "${installation_token}" '{}' | jq -r '.token'
}

get_remove_token() {
  local installation_token="$1"
  local url

  if [[ "${RUNNER_SCOPE}" == "org" ]]; then
    url="${GITHUB_API_URL}/orgs/${GITHUB_ORG}/actions/runners/remove-token"
  else
    url="${GITHUB_API_URL}/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/actions/runners/remove-token"
  fi

  api POST "${url}" "${installation_token}" '{}' | jq -r '.token'
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

  if [[ -f "/runner-tmp/.runner" ]]; then
    log 'Removing runner registration'

    local jwt installation_token remove_token
    jwt="$(make_jwt "${GITHUB_APP_ID}" "/runner-tmp/github-app.pem")"
    installation_token="$(get_installation_token "${jwt}")"
    remove_token="$(get_remove_token "${installation_token}")"

    ./config.sh remove --unattended --token "${remove_token}"
  fi

  rm -f /runner-tmp/github-app.pem
  exit "${exit_code}"
}

main() {
  trap cleanup EXIT INT TERM

  require_env GITHUB_APP_ID
  require_env GITHUB_APP_INSTALLATION_ID
  require_env GITHUB_APP_PRIVATE_KEY_B64
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
  printf '%s' "${GITHUB_APP_PRIVATE_KEY_B64}" | base64 -d >/runner-tmp/github-app.pem

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

  ./config.sh \
    --unattended \
    --replace \
    --ephemeral \
    --disableupdate \
    --url "${target_url}" \
    --token "${registration_token}" \
    --name "${runner_name}" \
    --labels "${RUNNER_LABELS}" \
    --work "${RUNNER_WORKDIR}"

  if [[ -n "${RUNNER_GROUP:-}" && "${RUNNER_SCOPE}" == "org" ]]; then
    log "Runner group requested: ${RUNNER_GROUP}"
  fi

  log 'Starting runner listener'
  ./run.sh
}

main "$@"
