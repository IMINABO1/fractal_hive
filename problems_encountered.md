# Problems Encountered

Problems we hit and problems we fear. No solutions here — solutions live in `journal.md`.

## Hit
- **Smart App Control blocks the OCaml toolchain.** SAC is enforced on this Windows 11
  machine (`VerifiedAndReputablePolicyState = 1`). `dune build` dies immediately with
  `CreateProcess(): An Application Control policy has blocked this file`. The blocked
  binary is `ocamldep.exe` (and its `.opt`/`.byte` variants) — dune needs it to compute
  module dependencies. The compilers themselves (`ocamlc`, `ocamlc.opt`, `ocamlopt.opt`)
  run fine; only `ocamldep` is blocked.
- **Native compilation is also blocked.** It invokes the mingw assembler/linker, which SAC
  blocks the same way. Both native and (dune-driven) bytecode paths are dead on this box.
- **`eval "$(opam env)"` inside a script** did not put `ocamlc` on PATH in this git-bash.

## Feared (no fix planned yet)
- `float` (double) precision caps how far we can zoom. Deep zooms will pixelate and
  eventually round to garbage; there is no arbitrary-precision path.
- Serial server: on large viewports / many tiles the fill is slow, since tiles render one
  request at a time.
- SAC would block any *native* artifact we ever produce (e.g. a standalone `.exe`). We are
  relying on staying in bytecode + `ocamlrun`; a future need for a native binary reopens this.
- Windows Firewall may prompt on socket bind for a new listener.
- Fast pan/zoom fires overlapping renders. Only guarded client-side by a render id — a slow
  server could still churn through stale tile requests before noticing it was superseded.
