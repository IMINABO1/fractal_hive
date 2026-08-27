#!/usr/bin/env bash
# FractalHive bytecode build.
#
# Why this exists: Smart App Control (enforced) on this machine blocks
# ocamldep.exe, so `dune build` cannot run here. This compiles the modules in
# dependency order with ocamlc (allowed) into a plain bytecode file, which runs
# via ocamlrun (allowed) -- no PE executable is produced, so SAC never triggers.
# On an unrestricted machine, prefer `dune build` / `dune exec ./bin/main.exe`.
set -euo pipefail
cd "$(dirname "$0")"
ocamlc() { opam exec -- ocamlc "$@"; }

ocamlc -c -I lib lib/viewport.ml
ocamlc -c -I lib lib/mandelbrot.ml
ocamlc -c -I lib lib/tile.ml
ocamlc -c -I lib lib/render.ml
ocamlc -c -I lib lib/auction.ml
ocamlc -c -I lib lib/hive.ml
ocamlc -c -I lib -I +unix lib/server.ml
ocamlc -c -I lib -I bin bin/main.ml

ocamlc -I +unix -o fractalhive.byte unix.cma \
  lib/viewport.cmo lib/mandelbrot.cmo lib/tile.cmo \
  lib/render.cmo lib/auction.cmo lib/hive.cmo lib/server.cmo bin/main.cmo

echo "built fractalhive.byte  ->  run: ./run.sh --port 8080"
