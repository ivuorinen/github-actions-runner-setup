# Rule: runner services drop ALL capabilities and re-add only the minimum

In `docker-compose.yml`, every runner service must declare:

```yaml
cap_drop:
  - ALL
cap_add:
  - CHOWN
  - DAC_OVERRIDE
  - FOWNER
  - SETGID
  - SETUID
  - KILL
```

This is the minimum set required for the GitHub Actions runner to
function:

| Cap | Why |
| --- | --- |
| `SETGID`, `SETUID` | `gosu` drops privileges from root entrypoint to the runner user |
| `CHOWN`, `FOWNER` | `actions-runner` extracts tarballs that record varying owners |
| `DAC_OVERRIDE` | Some `setup-*` actions assume this is available |
| `KILL` | The runner manages and signals its own worker child processes |

Everything else — `NET_RAW`, `NET_BIND_SERVICE`, `NET_ADMIN`, `SYS_CHROOT`,
`SYS_ADMIN`, `SYS_PTRACE`, `SYS_MODULE`, `MKNOD`, `AUDIT_WRITE`, `SETFCAP`,
`SETPCAP`, `FSETID`, `IPC_OWNER`, `IPC_LOCK`, `LINUX_IMMUTABLE`,
`BLOCK_SUSPEND`, `WAKE_ALARM`, `LEASE`, `BPF`, `PERFMON`, `CHECKPOINT_RESTORE`
— is dropped.

## Why this matters

Each capability granted to the runner container is a capability available
to any workflow that runs on it. `NET_RAW` allows ARP spoofing on the
container network; `SYS_PTRACE` defeats `kernel.yama.ptrace_scope=1` and
lets a workflow attach to the root entrypoint while it holds the GitHub
App PEM contents in memory; `SYS_ADMIN` is effectively root.

The runner image's `gosu` drop-privs path also means workflows execute
without `SETUID`/`SETGID` — those caps belong to the entrypoint, not the
job, and a non-trivial workflow attack would need them to escalate.

## What this rule forbids

Adding any capability to `cap_add:` that is not in the list above without
an explicit `# allow-cap-rule-12: <reason>` comment on the same line AND a
paragraph in `docs/SECURITY.md` documenting why the capability is needed
and what mitigations apply.

Particularly forbidden without justification:

- `SYS_ADMIN` — effectively container root
- `SYS_PTRACE` — defeats the PEM-in-root-memory isolation (rule 01)
- `NET_ADMIN`, `NET_RAW` — network attacks against sibling services
- `SYS_MODULE` — load kernel modules
- `MKNOD` — create device nodes

## Verification

```bash
yq -r '.services | to_entries[] | select(.key | test("^runner")) | .value.cap_add[]' docker-compose.yml | sort -u
```

The output must be a subset of: `CHOWN DAC_OVERRIDE FOWNER KILL SETGID SETUID`.
