(* A rectangular block of pixels: [x0, x1) x [y0, y1). *)

type t = {
  x0 : int;
  y0 : int;
  x1 : int;
  y1 : int;
}

let width t = t.x1 - t.x0
let height t = t.y1 - t.y0

(* Split a w x h image into a grid of at-most size x size tiles. *)
let split ~w ~h ~size =
  let tiles = ref [] in
  let y = ref 0 in
  while !y < h do
    let y1 = min (!y + size) h in
    let x = ref 0 in
    while !x < w do
      let x1 = min (!x + size) w in
      tiles := { x0 = !x; y0 = !y; x1; y1 } :: !tiles;
      x := x1
    done;
    y := y1
  done;
  List.rev !tiles
