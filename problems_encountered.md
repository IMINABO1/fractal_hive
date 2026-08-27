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
  (v2 update: replaced with real `AbortController` + cooperative server abort.)

## v2
### Hit
- Native compilation is blocked (SAC), so v2's parallelism runs in *bytecode* via `ocamlrun`.
  It genuinely parallelizes (measured up to 8.3x on 8 workers), but every render is slower than
  a native build would be — heavy zoomed views at high iters take seconds even parallelized.

### Feared (no fix planned yet)
- Serial accept loop: the server handles one connection at a time, so a new request is not
  accepted until the current render's workers stop. The browser's abort (socket close ->
  cooperative stop) covers the interactive case, but two tabs or a stray curl still queue.
- `Domain.spawn` per `/render` call (a fresh pool each request) costs a few ms of spawn/join
  overhead. Negligible now; a persistent domain pool is the real fix (v3).
- Streaming has no Content-Length and relies on `Connection: close` to signal the end. Any
  intermediary that buffers the response would defeat progressive fill (fine on localhost).
- The frontend re-copies the whole stream buffer on every chunk (`new Uint8Array` + `set`);
  O(n^2) in the worst case for very large frames. Fine at current sizes, not for 4K renders.

## v2.5
### Feared (no fix planned yet)
- Auto-iterations is capped at 4000, but the real ceiling is lower: past ~1e-14 scale, `float`
  (double) precision — not iteration count — limits the zoom, so very deep views degrade no
  matter how high `max_iter` goes. Arbitrary precision (perturbation/rebasing) is the only fix.
- More iterations = slower renders; the workers slider is the only counterweight, and on this
  bytecode-only machine there's no native speed to fall back on.
- The progress bar's total is computed client-side as `ceil(W/TILE)*ceil(H/TILE)`; if the tile
  size or dimensions ever diverge between client and server the bar would over/under-fill.
