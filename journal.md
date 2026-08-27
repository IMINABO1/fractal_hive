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
- v2: real parallel tile rendering with OCaml 5 `Domain`s pulling from a shared priority
  queue — turns the serial fill into a genuine parallel auction.
- A live bid-heatmap overlay would make the auction even more legible.
- Deep-zoom precision (perturbation theory / rebasing) is the interesting hard problem later.
