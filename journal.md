# Journal

Decisions, why we made them, problems + how we solved them, and stray thoughts.

## What this is
FractalHive: an interactive Mandelbrot renderer where image tiles **bid for compute**, so
the most detailed regions (the set's boundary) render first. It mirrors Jane Street's
real time compute auction on "the hive". Browser `<canvas>` frontend, OCaml backend over
stdlib `Unix` sockets.

## Why a client and server split instead of a static image
A fractal has infinite detail, so zooming means **rerendering at a new scale**, which needs
the compute engine in the loop, something a PNG cannot do. A browser canvas + an OCaml tile
server keeps OCaml as the compute engine and gives real interactivity. Bonus: a backend
compute service streaming data to a frontend is about the most Jane Street shaped
architecture we could pick.

## Why bid = variance of corner + center escape counts
A cheap proxy for "how much detail is in this tile." Boundary tiles see wildly different
escape counts across their corners (high variance); flat interior/exterior tiles see
near equal counts (low variance). Sorting tiles by bid descending makes the boundary paint
first: the auction, made visible. Verified: for the default view the top bids (~8800) all
sit in the center band where the boundary is.

## Problem: Smart App Control blocks the OCaml toolchain (solved)
`dune build` failed with "An Application Control policy has blocked this file." Traced it:
`ocamlc`/`ocamlc.opt`/`ocamlopt.opt` run, but `ocamldep.exe` (all variants) is blocked, and
dune needs `ocamldep`. SAC is enforced and has no per file exception; turning it off is
irreversible (needs a Windows reinstall), so we route around it rather than disable it.

**Solution:** skip dune on this machine. Compile the modules by hand in dependency order
with `ocamlc` into a *plain bytecode* file (`build.sh`) and run it with `ocamlrun`
(`run.sh`). SAC blocks unknown PE executables, but a `.byte` is data executed by the
already trusted `ocamlrun`, so nothing is blocked. Confirmed the bytecode and the `unix` C
stubs (`dllunix`) run fine under SAC. The `dune-project`/`dune` files are kept so
`dune build` still works normally on an unrestricted machine.

## Why `(wrapped false)` on the library
So the same module names (`Server`, `Viewport`, ...) resolve under both build paths. dune's
wrapped namespace would be `Fractalhive.Server`, but the manual bytecode build produces
unwrapped top level modules. Unwrapping keeps one `bin/main.ml` working for both.

## Thoughts / next
- A live bid heatmap overlay would make the auction even more legible.
- Deep zoom precision (perturbation theory / rebasing) is the interesting hard problem later.

## v2 parallel auction
The v1 "auction" was only a sort: one worker, no contention. v2 makes tiles actually compete
for compute. New `lib/hive.ml` runs the render across N `Domain` workers pulling from one
shared bid ordered queue.

Why an atomic cursor instead of a mutex guarded heap: `Auction.plan` already returns tiles
sorted by bid, so the "queue" is just that array plus `Atomic.fetch_and_add` on a cursor.
Claiming the next highest bid is then lock free, lower index = higher bid. The only shared
mutable step is writing the rendered tile to the socket, so a single `Mutex` guards that;
rendering itself touches disjoint pixels and needs no lock.

Server side, not client side: the compute is the "hive", so parallelism belongs on the
server. A new `/render` endpoint streams framed tiles (16 byte header x0,y0,x1,y1 int32 LE +
RGBA, no `Content-Length`, ends on connection close). The browser reads the stream and paints
tiles as they land, so progressive fill survives.

Cooperative cancellation: `emit` returns false when the socket write fails (client gone),
which flips a shared `aborted` atomic so workers stop claiming. The frontend drives this with
an `AbortController`: a new render aborts the old fetch, the socket closes, the server bails.
Cleaner than v1's render id guard because it actually frees the server.

Verified on this machine (bytecode, `ocamlrun`): render time 1w=51.7s, 2w=20.5s, 4w=10.1s,
8w=6.2s (8.3x) on a heavy zoomed view at 400 iters, real multicore scaling. Reconstructed a
streamed frame into a PNG: clean Mandelbrot, no tearing, byte counts exact (pixels + one
16 byte header per tile), so the concurrent mutex guarded writes don't interleave.

Decision: keep `/tile` and `/plan` around (the PNG preview tooling uses `/tile`); the browser
now uses `/render`. `--workers` sets the server default; `?workers=` overrides per request, and
the `[`/`]` keys change it live so the speedup is something you can feel.

## v2.5 UX polish
Loader + done indicator (determinate progress bar over the known tile total + a braille
spinner + a `✓ N tiles · X ms` line), a visible workers slider (mirrors the `[`/`]` keys), and
**auto iterations**: the client scales `max_iter` up with zoom depth
(`clamp(200 + 40*log2(0.005/scale), 200, 4000)`) and passes it as `?iters=`; the server honors
it with the `--iters` default as the floor. HUD now shows workers, iters, tiles/total, and ms.

## Two infinities (note to future me)
When I was adding a "speed" dial I got briefly confused about whether a render could run
forever, and untangling it is worth remembering:

- **A single frame is finite and always terminates.** Fixed box + fixed pixel resolution = a
  fixed pixel count, and each pixel runs the escape loop *at most* `max_iter` times. That cap
  IS the deterministic stopping point. Points in the black interior never escape, so they're
  the expensive ones, always running the full `max_iter` before we give up and call them
  black. No cap would mean they loop forever; the cap is what guarantees termination.
- **The infinite detail lives only across zoom levels.** You can keep zooming forever and
  always find new structure (those "infinitely minute black spaces"), but each individual zoom
  is still one finite frame. The infinity is in the *sequence* of zooms, not inside any frame.

That's the whole reason auto iterations exists: deeper zoom needs a higher cap or the fine
black filaments blur into blobs, but every frame still finishes. Pixel size (resolution) sets
how much of that detail you can even sample; below ~1e-14 scale `float` precision, not
iterations, is what finally kills the zoom.

## v2.6 controlled zoom
Trackpad users (no mouse) kept over zooming: the wheel handler applied a fixed 0.8x/1.25x step
*per event*, and a trackpad fires many events per gesture. Fixed both ends: added explicit
zoom in / zoom out / reset buttons (and `+`/`-`/`0` keys) that zoom in deliberate steps about
the canvas center, and made the wheel proportional to `deltaY` (`Math.pow(1.0015, deltaY)`) so
a small scroll is a small zoom. Refactored the shared math into `zoomAt(mx, my, factor)`:
buttons pass the center, the wheel passes the cursor. Frontend only; no server change.

## v3 sharded markets + arbitrage (the headline result)
Generalized `hive.ml` into `lib/market.ml` and deleted hive (markets=1 reproduces it). The
image splits into k markets (vertical bands), each a bid sorted queue + atomic cursor; workers
have a home market (`home = id mod k`). Siloed: a worker serves only its home, then idles.
Arbitrage: a drained worker steals the highest front bid tile from any market, reglobalizing
the auction. Per worker render time is recorded (each worker writes only its own slot) so
`/stats` can run both modes and return utilization; the browser draws the two as bar rows.

The measured result (markets=4, workers=8, default view, 300 iters):
- **siloed** 3661 ms, mean utilization ~35%, two workers pinned near 100% on the boundary
  bands while others sat at ~5% (their light bands drained and they idled).
- **arbitrage** 1499 ms, mean utilization ~88%, every worker 80 to 99%.
- **2.44x faster** purely from letting idle workers cross market lines.

That's the whole thesis, empirically: siloed compute wastes cycles, and arbitrage (a global
auction) recovers them, which is exactly why Jane Street runs one global auction on the hive
instead of per desk clusters. `tint` blends a per market hue into tiles so the k bands are
visible in the render.

## Next (v4, optional)
Persistent domain pool (kill the per request spawn/join), a live per market utilization overlay
during a render, and deep zoom precision (perturbation/rebasing) past the float floor.
