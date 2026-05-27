# Rule: PEM must be root:root mode 600 on the host

The GitHub App private key (PEM) must be owned by `root:root` (UID 0, GID 0)
with permissions `0600` on the Docker host. `entrypoint.sh` enforces this at
container start and refuses to run otherwise.

## Why

The PEM is bind-mounted read-only into every runner container at
`/run/secrets/github_app_key`. Inside the container, `entrypoint.sh` runs as
root, reads the PEM into root-process memory to mint the JWT, then drops
privileges via `gosu` to the runner user (UID 1001) before exec'ing
`config.sh` and `run.sh`. Because the PEM is owned by UID 0 mode 600, the
runner user — and therefore any workflow job — **cannot** read it.

If the host-side mode is relaxed (e.g. 640, 644), workflow jobs inherit that
relaxation through the bind mount and can read the PEM directly. The host
permission is the only defense.

## How to verify

```bash
stat -c '%U %G %a' /etc/github-app/private-key.pem
# Expected output: root root 600
```

If it shows anything else, fix with:

```bash
chown 0:0 /etc/github-app/private-key.pem
chmod 600 /etc/github-app/private-key.pem
```

## How `entrypoint.sh` enforces this

`scripts/entrypoint.sh` calls `stat -c '%u'` and `stat -c '%a'` on
`${GITHUB_APP_PRIVATE_KEY_FILE}` and refuses to start unless owner is `0`
and mode has no group/other access bits set
(`((((8#${mode}) & 077)) == 0)` — note the load-bearing inner parens; see
rule 09).

See `docs/SECURITY-REVIEW-2026-04-20.md` finding **H-1**.
