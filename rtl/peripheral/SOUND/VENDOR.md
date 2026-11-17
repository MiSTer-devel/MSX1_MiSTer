# Third-party sound cores

Copied into the tree from upstream (formerly git submodules). Only the license, the README and
the HDL sources are kept.

| Directory | Upstream | Commit | Paths taken |
|---|---|---|---|
| `jt51` | https://github.com/jotego/jt51 | `2ca6601e6e69e1a3a529920506ee0657ccd30513` | `LICENSE`, `README.md`, `hdl/` |
| `ikaopll` | https://github.com/ika-musume/IKAOPLL | `4d393238d1be33ea428a454956270504f037dfa3` | `LICENSE`, `README.md`, `src/` |
| `jt49` | https://github.com/jotego/jt49 | unknown | `LICENSE`, `README.md`, `hdl/`, `syn/quartus/jt49.qip` |

## Updating

1. Take the local changes as a patch: `git diff <import commit> HEAD -- <directory>`, where the
   import commit is the last one that copied upstream unchanged.
2. Replace the directory with the same paths from the new upstream commit and commit it
   unchanged (the next import commit).
3. Apply the patch, resolve conflicts, update the table above.
