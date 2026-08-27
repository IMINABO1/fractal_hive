(* Escape count -> (r, g, b). Interior (never escaped) is black; the rest uses a
   smooth polynomial palette that runs blue -> orange -> white near the edge. *)
let color ~max_iter count =
  if count >= max_iter then (0, 0, 0)
  else begin
    let t = float_of_int count /. float_of_int max_iter in
    let clamp v = max 0 (min 255 (int_of_float v)) in
    let r = clamp (9.0 *. (1.0 -. t) *. t *. t *. t *. 255.0) in
    let g = clamp (15.0 *. (1.0 -. t) *. (1.0 -. t) *. t *. t *. 255.0) in
    let b = clamp (8.5 *. (1.0 -. t) *. (1.0 -. t) *. (1.0 -. t) *. t *. 255.0) in
    (r, g, b)
  end

(* Render one tile to a raw RGBA buffer (row-major, 4 bytes/pixel). *)
let render_tile ~vp ~max_iter (tile : Tile.t) =
  let tw = Tile.width tile and th = Tile.height tile in
  let buf = Bytes.create (tw * th * 4) in
  for j = 0 to th - 1 do
    for i = 0 to tw - 1 do
      let px = tile.Tile.x0 + i and py = tile.Tile.y0 + j in
      let c = Viewport.to_complex vp ~px ~py in
      let count = Mandelbrot.escape ~max_iter c in
      let (r, g, b) = color ~max_iter count in
      let o = (j * tw + i) * 4 in
      Bytes.set buf o (Char.chr r);
      Bytes.set buf (o + 1) (Char.chr g);
      Bytes.set buf (o + 2) (Char.chr b);
      Bytes.set buf (o + 3) '\255'
    done
  done;
  buf
