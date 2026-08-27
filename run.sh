#!/usr/bin/env bash
# Run the bytecode build via ocamlrun (SAC-safe). Args pass through, e.g.
#   ./run.sh --port 8080 --iters 300
cd "$(dirname "$0")"
exec opam exec -- ocamlrun fractalhive.byte "$@"
