# Rule: bash arithmetic — `&` and `==` precedence (over-parenthesize)

In bash arithmetic (`(( ... ))`), the equality operators `==` and `!=` have
**higher** precedence than the bitwise operators `&`, `^`, `|`. This is
inherited from C and is the opposite of what most people expect when
reading the expression left-to-right.

## The trap

```bash
mode=600
(((8#${mode}) & 077 == 0)) && echo ok || echo bad
```

The natural-language reading is "AND-mask `mode` against `077`, then
compare to zero", which should succeed for mode `600`. But the actual
parse is:

```text
(8#${mode}) & (077 == 0)   == (8#600) & 0
                            == 384 & 0
                            == 0
```

And `((0))` returns exit status 1 — **the test always fails**, regardless
of mode. This bug was present in `scripts/entrypoint.sh` until passing the
nitpicker pass and would have blocked every container start in production.

## The fix: over-parenthesize

Always wrap the bitwise expression and the comparison separately:

```bash
((((8#${mode}) & 077) == 0)) && echo ok || echo bad   # correct
```

`shellcheck` does not catch this. `shfmt` does not catch this. There is no
automated linter for it. **Review by eye on every change to arithmetic
involving mask + compare.**

## Other affected operators

The same risk applies to:

- `(a & b == c)` — parses as `a & (b == c)`
- `(a | b == c)` — parses as `a | (b == c)`
- `(a ^ b == c)` — parses as `a ^ (b == c)`
- `(a << b == c)` — parses as `(a << b) == c` ✓ (shifts are higher than `==`)
- `(a > b & c)` — parses as `(a > b) & c` — `>` is higher than `&`

When in doubt: `((  (a OP b) CMP c  ))`.

## Verification

```bash
grep -nE '\(\([^()]*[&|^][^()]*==' scripts/entrypoint.sh
```

If this matches, audit the expression for the operator-precedence bug.
