# Rule: never log token material

The following values must never be printed to stdout, stderr, or any log
sink, even at debug level:

- `${jwt}` — GitHub App JWT (RS256-signed, 9-minute lifetime)
- `${installation_token}` — Installation access token (1-hour lifetime,
  identifiable by `ghs_` prefix; GitHub flags these in scanning)
- `${registration_token}` — Runner registration token (1-hour lifetime)
- `${remove_token}` / `${RUNNER_REMOVE_TOKEN}` — Runner remove token
- raw response bodies from `/app/installations/*/access_tokens` or
  `/actions/runners/registration-token` or `/actions/runners/remove-token`
- the PEM contents (`${GITHUB_APP_PRIVATE_KEY_FILE}` itself, not just the
  path)

## Why

Any of these grant the ability to register a runner on the target org or
repo, or to take actions as the GitHub App. Logs are persisted (Docker
json-file driver, syslog, Coolify) and routinely searched, copy-pasted into
chat, attached to bug reports. A single leaked token has the same blast
radius as the credential itself for up to 1 hour.

## What is OK to log

- The presence/absence of a token (`"token obtained"`, `"no remove token"`)
- The number of characters or the SHA-256 prefix, when debugging is required
- The expiry timestamp from the API response
- The HTTP status code of the API call
- The runner name, URL, labels

## Pattern to enforce

Use `log "Obtained installation token"` rather than
`log "token=${installation_token}"`. If you need to confirm a token was
returned, check its length: `[[ -n "${token}" ]]`.

## How to verify

```bash
grep -nE 'log .*\$\{?(jwt|installation_token|registration_token|remove_token|RUNNER_REMOVE_TOKEN)' scripts/entrypoint.sh
```

Must produce no matches.

The `.claude/hooks/warn-entrypoint-token-handling.sh` hook flags edits that
touch token-handling code, but it does not detect logging — review by eye.
