# Contributing

Thanks for taking the time to improve this project.

## Before you start

1. Read `docs/ARCHITECTURE.md` and `docs/SECURITY.md`. The system has
   a small but unusual security model (root entrypoint, UID-isolated
   PEM, privilege drop via gosu); changes that move that boundary need
   careful review.
2. Read `.claude/rules/`. Each rule documents an invariant that the
   review process has learned the hard way. New PRs are evaluated
   against these rules.
3. Run `pre-commit install` once after cloning. This wires up the
   shellcheck / shfmt / yamllint / markdownlint / actionlint / checkov
   pre-commit hooks.

## Development setup

```bash
git clone https://github.com/ivuorinen/github-actions-runner-setup.git
cd github-actions-runner-setup
make install-hooks   # = pre-commit install
make lint            # = pre-commit run --all-files
```

You do not need a working GitHub App PEM for most changes — the lint
suite covers shell, YAML, and Markdown without running the entrypoint.

## Making a change

### Style

- Shell: 2-space indent, `set -Eeuo pipefail`, `local` for all function
  variables, prefer `printf` over `echo`, no `cd` in the entrypoint
  (rule 10).
- YAML: 2-space indent, max 200 chars, `---` document marker on top.
- Markdown: 2-space indent, max 200 chars, ATX headers, fenced code
  blocks with language.
- Dockerfile: digest-pin every `FROM` (rule 06), comment intent for any
  `RUN` that downloads or extracts.

### What requires a security review

Any change to:

- `scripts/entrypoint.sh` token handling, cleanup trap, signal handling
- `Dockerfile` USER directive, base image, package list
- `docker-compose.yml` capabilities, security_opt, volumes,
  socket-proxy config
- `.claude/rules/` or `.claude/hooks/*` (these guard the boundary)

Tag `@ivuorinen` on the PR and mention the security implications in the
description.

### Tests

There is no functional test suite (the system is integration-only — it
needs a real GitHub App). The lint suite is the gate:

```bash
make lint
```

Manual verification for a runner change:

```bash
make build                   # docker compose build
make up                      # docker compose up -d
docker compose logs -f       # observe registration / job pickup
# trigger a workflow on GitHub
make down                    # docker compose down
```

### Commits

- Conventional commits: `type(scope): subject`. Types: `feat`, `fix`,
  `chore`, `docs`, `refactor`, `test`, `ci`, `build`.
- Subject ≤ 70 chars. Body wraps at 80.
- Reference the issue or finding ID in the body if applicable
  (`Fixes #N`, `Resolves H-1`).

### Pull requests

- One logical change per PR.
- Update `docs/` if behaviour or env vars change.
- Update `.env.example` and `docs/ENVIRONMENT-VARIABLES.md` together.
- Update `CHANGELOG.md` (if present) with a one-liner under "Unreleased".
- Pass CI (Docker build + lint suite) before requesting review.

## Adding a new `.claude/` artifact

- **New hook**: place in `.claude/hooks/<verb>-<subject>.sh`, make
  executable, register in `.claude/settings.json`, document its trigger
  and rationale in a one-line comment at the top.
- **New rule**: place in `.claude/rules/<NN>-<slug>.md` with the next
  numeric prefix, add an entry to `.claude/rules/README.md`.
- **New skill**: place in `.claude/skills/<name>/SKILL.md`. Rare — most
  guidance belongs in `.claude/rules/`.

## Releasing

This project does not produce release artefacts other than the Docker
image. Releases are tag-only (`vX.Y.Z` on `main`). The CI Docker build
runs on every push to `main`.

## Questions

Open a GitHub discussion or email `ismo@ivuorinen.net`.
