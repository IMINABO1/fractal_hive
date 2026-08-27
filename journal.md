# Journal

Decisions, why we made them, problems + how we solved them, and stray thoughts.

## What this is
FractalHive: an interactive Mandelbrot renderer where image tiles **bid for compute**, so
the most detailed regions (the set's boundary) render first. It mirrors Jane Street's
real-time compute auction on "the hive". Browser `<canvas>` frontend, OCaml backend over
stdlib `Unix` sockets.

## Why client–server instead of a static image
A fractal has infinite detail, so zooming means **re-rendering at a new scale** — that needs
the compute engine in the loop, which a PNG cannot do. A browser canvas + an OCaml tile
server keeps OCaml as the compute engine and gives real interactivity. Bonus: a backend
compute service streaming data to a frontend is about the most Jane-Street-shaped
architecture we could pick.

## Why bid = variance of corner + center escape counts
A cheap proxy for "how much detail is in this tile." Boundary tiles see wildly different
escape counts across their corners (high variance); flat interior/exterior tiles see
near-equal counts (low variance). Sorting tiles by bid descending makes the boundary paint
first — the auction, made visible. Verified: for the default view the top bids (~8800) all
sit in the center band where the boundary is.

## Problem: Smart App Control blocks the OCaml toolchain (solved)
`dune build` failed with "An Application Control policy has blocked this file." Traced it:
`ocamlc`/`ocamlc.opt`/`ocamlopt.opt` run, but `ocamldep.exe` (all variants) is blocked, and
dune needs `ocamldep`. SAC is enforced and has no per-file exception; turning it off is
irreversible (needs a Windows reinstall), so we route around it rather than disable it.

**Solution:** skip dune on this machine. Compile the modules in hand-known dependency order
with `ocamlc` into a *plain bytecode* file (`build.sh`) and run it with `ocamlrun`
(`run.sh`). SAC blocks unknown PE executables, but a `.byte` is data executed by the
already-trusted `ocamlrun`, so nothing is blocked. Confirmed the bytecode and the `unix` C
stubs (`dllunix`) run fine under SAC. The `dune-project`/`dune` files are kept so
`dune build` still works normally on an unrestricted machine.

## Why `(wrapped false)` on the library
So the same module names (`Server`, `Viewport`, ...) resolve under both build paths. dune's
wrapped namespace would be `Fractalhive.Server`, but the manual bytecode build produces
unwrapped top-level modules. Unwrapping keeps one `bin/main.ml` working for both.

## Thoughts / next
- A live bid-heatmap overlay would make the auction even more legible.
- Deep-zoom precision (perturbation theory / rebasing) is the interesting hard problem later.

## v2 — parallel auction
The v1 "auction" was only a sort: one worker, no contention. v2 makes tiles actually compete
for compute. New `lib/hive.ml` runs the render across N `Domain` workers pulling from one
shared bid-ordered queue.

Why an atomic cursor instead of a mutex-guarded heap: `Auction.plan` already returns tiles
sorted by bid, so the "queue" is just that array plus `Atomic.fetch_and_add` on a cursor.
Claiming the next-highest bid is then lock-free — lower index = higher bid. The only shared
mutable step is writing the rendered tile to the socket, so a single `Mutex` guards that;
rendering itself touches disjoint pixels and needs no lock.

Server-side, not client-side: the compute is the "hive", so parallelism belongs on the
server. A new `/render` endpoint streams framed tiles (16-byte header x0,y0,x1,y1 int32-LE +
RGBA, no Content-Length, ends on connection close). The browser reads the stream and paints
tiles as they land, so progressive fill survives.

Cooperative cancellation: `emit` returns false when the socket write fails (client gone),
which flips a shared `aborted` atomic so workers stop claiming. The frontend drives this with
an `AbortController` — a new render aborts the old fetch, the socket closes, the server bails.
Cleaner than v1's render-id guard because it actually frees the server.

Verified on this machine (bytecode, `ocamlrun`): render time 1w=51.7s, 2w=20.5s, 4w=10.1s,
8w=6.2s (8.3x) on a heavy zoomed view at 400 iters — real multicore scaling. Reconstructed a
streamed frame into a PNG: clean Mandelbrot, no tearing, byte counts exact (pixels + one
16-byte header per tile), so the concurrent mutex-guarded writes don't interleave.

Decision: keep `/tile` and `/plan` around (the PNG-preview tooling uses `/tile`); the browser
now uses `/render`. `--workers` sets the server default; `?workers=` overrides per request, and
the `[`/`]` keys change it live so the speedup is something you can feel.

## Next (v3, the multi-market idea)
Shard the image into k markets, each a queue + worker pool in parallel, then add cross-market
work-stealing = arbitrage, and instrument per-worker utilization to show why one global auction
beats siloed ones. `hive.ml` (atomic-cursor queue + domain workers) is the reusable unit.
