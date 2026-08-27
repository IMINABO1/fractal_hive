(* The auction. Each tile bids for compute based on how much detail it likely
   holds: sample the escape count at the four corners and the center, and bid the
   variance. A tile straddling the set's boundary sees wildly different counts
   (high variance -> high bid); a flat interior or exterior tile sees near-equal
   counts (low variance -> low bid). Highest bidders render first. *)

let bid ~vp ~max_iter (tile : Tile.t) =
  let sample px py =
    float_of_int (Mandelbrot.escape ~max_iter (Viewport.to_complex vp ~px ~py))
  in
  let mx = (tile.Tile.x0 + tile.Tile.x1) / 2
  and my = (tile.Tile.y0 + tile.Tile.y1) / 2 in
  let samples =
    [ sample tile.Tile.x0 tile.Tile.y0;
      sample (tile.Tile.x1 - 1) tile.Tile.y0;
      sample tile.Tile.x0 (tile.Tile.y1 - 1);
      sample (tile.Tile.x1 - 1) (tile.Tile.y1 - 1);
      sample mx my ]
  in
  let n = float_of_int (List.length samples) in
  let mean = List.fold_left ( +. ) 0.0 samples /. n in
  List.fold_left (fun acc s -> acc +. ((s -. mean) ** 2.0)) 0.0 samples /. n

(* Tiles paired with their bid, sorted highest-bid first. *)
let plan ~vp ~max_iter tiles =
  tiles
  |> List.map (fun t -> (t, bid ~vp ~max_iter t))
  |> List.sort (fun (_, a) (_, b) -> compare b a)
