# FractalHive

**An interactive Mandelbrot renderer where image tiles bid for compute — a working
miniature of a real-time compute auction.** Written in OCaml (stdlib only), with a browser
canvas frontend talking to a tile server over raw sockets.

![A deep zoom into the Mandelbrot boundary](docs/deep-zoom.png)

## The idea

Rendering a fractal is embarrassingly parallel, but the tiles are *not* equal: a tile on the
set's boundary is expensive and full of detail, while a tile in empty space is cheap and
uniform. So you have a pile of compute jobs of wildly different value and cost — exactly the
situation a market solves.

FractalHive treats each tile as a **bidder**. A tile bids the variance of the escape counts at
its corners and center: high variance means it straddles the boundary (lots of detail), so it
bids high and renders first. Workers are the scarce resource; the highest bidders win them.

Zoom in and you *watch* the boundary sharpen before the flat regions fill — the auction, made
visible.

## The result: why one global auction beats silos

The interesting version shards the image into *k* **markets** (vertical bands), each with its
own queue and a share of the workers. Left alone (**siloed**), a light market's workers finish
early and sit idle while a heavy boundary market starves. Turn on **arbitrage** — an idle
worker steals the highest-bidding tile from any market — and the wasted compute comes back.

Measured (4 markets, 8 workers, default view):

| Mode | Wall time | Mean worker utilization |
|------|----------:|------------------------:|
| Siloed (no stealing) | 3661 ms | ~35% |
| **Arbitrage (work-stealing)** | **1499 ms** | **~88%** |

**2.44× faster**, purely from letting idle workers cross market lines. The `benchmark` button in
the UI draws this as per-worker utilization bars; the tinted bands below show the four markets.

![The image split into four tinted markets](docs/markets.png)

## Run it

Needs OCaml (5.x) + dune via opam. On a normal machine:

```bash
dune exec bin/main.exe -- --port 8080 --workers 8
```

This project was built on a Windows machine with **Smart App Control enforced**, which blocks
`ocamldep` and the native toolchain — so `dune build` can't run there. The workaround is a
plain-bytecode build that runs via `ocamlrun` (SAC allows bytecode; it's data, not a PE):

```bash
bash build.sh                 # compiles to fractalhive.byte with ocamlc, no ocamldep
bash run.sh --port 8080 --workers 8
```

Then open **http://localhost:8080**. Drag to pan, scroll or `−`/`+` to zoom, move the workers
slider, pick a market count, toggle arbitrage, and hit **benchmark**.

## Architecture

```
browser <canvas>  ──HTTP──▶  OCaml tile server ("the hive")
  pan/zoom/controls            /render  stream framed tiles, rendered in parallel
  paints tiles as they         /stats   benchmark siloed vs arbitrage -> utilization JSON
  stream in
```

- **`lib/mandelbrot.ml`** — escape-time iteration over stdlib `Complex`.
- **`lib/auction.ml`** — the bid (escape-count variance) and the bid-sorted plan.
- **`lib/market.ml`** — the parallel engine: *k* markets as bid-sorted arrays + atomic cursors,
  `Domain` workers claiming lock-free via `Atomic.fetch_and_add`, home markets, and arbitrage
  work-stealing. Per-worker render time is recorded for the utilization stats.
- **`lib/server.ml`** — a minimal HTTP/1.1 server on stdlib `Unix` sockets; streams tiles
  (16-byte header + RGBA) with a `Mutex` guarding only the socket write.
- **`web/index.html`** — canvas frontend, no JS libraries; reads the tile stream with an
  `AbortController` for cooperative cancellation.

No external libraries — just OCaml's `Complex`, `Unix`, `Domain`, `Atomic`, and `Mutex`.

## How it got here

- **v1** — single-threaded renderer streaming tiles in bid order over sockets.
- **v2** — N parallel `Domain` workers pulling from one shared bid queue (measured up to 8.3×).
- **v2.5 / v2.6** — loader, live worker control, zoom that auto-scales iterations, zoom buttons.
- **v3** — sharded markets + work-stealing arbitrage + the utilization benchmark above.

See `journal.md` for the design decisions and `problems_encountered.md` for the sharp edges.
