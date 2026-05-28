# Rule: `Dockerfile` must not `COPY . .` or `ADD .`

In `Dockerfile`, every `COPY` and `ADD` source must be an explicit path
(file or sub-tree). A blanket copy of the entire build context is
forbidden.

The currently allowed `COPY` shape is the per-file form:

```dockerfile
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
```

## Why

`COPY . .` (or `COPY . /opt/foo`) brings the entire build context into
the image layer. The build context routinely contains:

- `.env` — if an operator copies `.env.example` to `.env` and then builds
  the image locally without `--no-cache`, the secrets land in the image
  layer and any subsequent push or `docker save` exfiltrates them.
- `.git/` — the entire git history, which leaks branch names, author
  emails, prior commit messages, and any file ever committed.
- `*.pem`, `*.key` — the GitHub App private key if the operator stages
  it locally for a one-off `make build`.
- `.claude/settings.local.json` — per-machine Claude config which may
  contain telemetry-relevant identifiers.

`.dockerignore` provides defense-in-depth (it excludes `.env`, `*.pem`,
`.git`, `secrets/`, `.claude/` and similar). But `.dockerignore` and
`COPY .` together is one mis-edit away from a leak: a contributor who
adds a new sensitive directory and forgets to update `.dockerignore`
ships a leaky image silently. Per-file `COPY` makes the leak impossible
by construction — only the files explicitly named end up in the image.

## What this rule forbids

In `Dockerfile`, none of the following shapes are allowed:

```dockerfile
COPY . .                          # forbidden — entire context
COPY . /opt/whatever              # forbidden — entire context
COPY ./ /opt/whatever             # forbidden — entire context
ADD . /opt/whatever               # forbidden — entire context AND auto-extract
ADD https://example.com/x.tgz /   # forbidden — opaque external download
```

## Acceptable alternatives

```dockerfile
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/ /usr/local/bin/scripts/        # OK — subtree, not whole context
COPY --from=builder /out/bin /usr/local/bin  # OK — multi-stage copy
```

If a new directory genuinely needs to be in the image, create it under
`scripts/` (or another existing top-level directory already in
`.dockerignore`'s allow set) and `COPY` it by name.

## Verification

```bash
grep -nE '^(COPY|ADD)[[:space:]]+(\.|\./)([[:space:]]|$)' Dockerfile
```

Must produce no output.

`ADD <URL>` is also flagged by hadolint (DL3020) but the rule above is
the explicit invariant for this repo.
