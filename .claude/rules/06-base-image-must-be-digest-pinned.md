# Rule: every `FROM` and `image:` must include an SHA-256 digest

In `Dockerfile` and `docker-compose.yml`, every image reference must include
the immutable digest in addition to the human-readable tag:

```text
FROM ghcr.io/actions/actions-runner:2.334.0@sha256:b6614fce332517f74d0a76e7c762fb08e4f2ff13dcf333183397c8a5725b6e8e
image: tecnativa/docker-socket-proxy:0.4.2@sha256:1f3a6f303320723d199d2316a3e82b2e2685d86c275d5e3deeaf182573b47476
```

## Why

A tag is a mutable label that the registry maintainer can repoint at any
time. A digest is the cryptographic identity of the image content. Tag-only
references are vulnerable to:

- **Registry compromise** — an attacker pushes a malicious image to the
  same tag and every `docker pull` ships it.
- **Silent base-image breakage** — the maintainer republishes `latest` or
  `2.334.0` with different contents and your runners pick it up on next
  rebuild.
- **Reproducibility loss** — `docker build` two weeks apart produces
  different layers.

## How Renovate keeps this current

`.github/renovate.json` extends `github>ivuorinen/renovate-config`. Renovate
opens a PR to bump both the tag AND the digest in lockstep — see recent
commits like
[`654fea0`](https://github.com/ivuorinen/github-actions-runner-setup/commit/654fea0).

Manually editing the tag without the digest is forbidden.

## Verification

```bash
grep -nE '^FROM ' Dockerfile | grep -v '@sha256:'
grep -nE 'image:' docker-compose.yml | grep -v '@sha256:'
```

Both must produce no output.

Enforced at PR time by `.claude/hooks/block-unpinned-base-image.sh`.
