# Rule: `entrypoint.sh` must not `cd` away from `/home/runner`

The `Dockerfile` sets `WORKDIR /home/runner`. `tini` starts
`/usr/local/bin/entrypoint.sh` from that directory. Multiple call sites in
the script invoke `./config.sh` (registration and removal) and `./run.sh`
(runner listener) as relative paths.

If any code path runs `cd` to a different directory, `./config.sh` becomes
unresolvable, which breaks:

- the initial registration call in `main()`
- the `deregister_runner()` cleanup call (which runs from the `EXIT` trap)

The cleanup path is especially dangerous because the failure is silent —
the cleanup runs at container shutdown, the error message goes to the
docker logs but the container is also exiting, and the runner stays
registered on GitHub indefinitely.

## What this rule forbids

```bash
cd /tmp                            # forbidden
pushd "${some_dir}" && ...         # forbidden
(cd "${dir}" && ./something)       # acceptable IF you do not invoke
                                   # config.sh/run.sh inside the subshell
```

## Acceptable alternatives

If you genuinely need to operate on files in another directory, use absolute
paths:

```bash
ls -la /var/tmp/x                  # OK — no cd
gosu runner /home/runner/config.sh # OK — absolute path
```

## Verification

```bash
grep -nE '\b(cd|pushd|popd)\b' scripts/entrypoint.sh
```

Must produce no matches (other than this rule file's own example block).
