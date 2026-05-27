# Roadmap

Completed items from the original `Next steps` list have been folded into the
shipping codebase. The remaining items below are future improvements that are
deferred but tracked.

## Done

- [x] **Pinned image tags instead of `latest`** — both the base image and
  the socket-proxy are digest-pinned and managed by Renovate. See
  `.claude/rules/06-base-image-must-be-digest-pinned.md`.
- [x] **A `Makefile` for local operations** — see `Makefile`. Covers
  `lint`, `build`, `up`, `down`, `logs`, `audit`, and friends.
- [x] **Dedicated runner groups** — supported via `RUNNER_GROUP` env var
  for org-scoped runners. See `docs/ENVIRONMENT-VARIABLES.md#runner_group`.

## In progress / future

- [ ] **Split trusted/untrusted runner pools.** Today, every runner has the
  same labels and the same socket-proxy. A future version should support
  a second runner pool with stricter `CONTAINERS` deny (no
  `docker build`), tighter capabilities, and isolation from the trusted
  pool's network namespace. Tracked as an architectural change because
  it requires a second compose file or profile.
- [ ] **Optional repo allow-listing.** Today the App's installation
  controls which repos can request runners. Add a runtime check in
  `entrypoint.sh` that refuses to register against a repo that is not
  in a configured allow-list, regardless of installation scope. Useful
  for org-scoped setups where the App is installed broadly but only a
  subset of repos should be allowed to use these specific runners.
- [ ] **Preinstalled common linters/tools in the runner image.** The
  base image already includes Node, Python, Go, Ruby, but workflows
  often spend cold-start time on `apt-get install jq` / shellcheck /
  shfmt. Investigate whether a derived image with a curated tool set
  pays back its size cost.
- [ ] **Egress filter for runners.** Default-deny outbound except to
  `api.github.com`, `*.ghcr.io`, `*.actions.githubusercontent.com`,
  and the operator's package registries. Today this must be done at
  the host firewall level; consider adding a per-container egress
  proxy.
- [ ] **Per-runner OpenTelemetry metrics.** Cold-start time, job
  duration, token-mint latency. Currently visible only in logs.
- [ ] **OIDC token integration documentation.** Workflows can use
  GitHub OIDC tokens to authenticate to AWS/GCP/Azure without
  long-lived secrets. The runners support this transparently (it is a
  GitHub Actions feature, not ours), but the docs do not call it out.

Open a GitHub issue at
<https://github.com/ivuorinen/github-actions-runner-setup/issues> if you
want one of these prioritised.
