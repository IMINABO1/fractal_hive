(* A viewport maps image pixels onto a rectangle of the complex plane. *)

type t = {
  cx : float;    (* center, real axis *)
  cy : float;    (* center, imaginary axis *)
  scale : float; (* complex units per pixel *)
  w : int;       (* image width in pixels *)
  h : int;       (* image height in pixels *)
}

let make ~cx ~cy ~scale ~w ~h = { cx; cy; scale; w; h }

(* Pixel (px, py) -> point in the complex plane. Screen y grows downward, so
   the imaginary axis is flipped to keep "up" positive. *)
let to_complex t ~px ~py =
  let re = t.cx +. (float_of_int px -. float_of_int t.w /. 2.0) *. t.scale in
  let im = t.cy -. (float_of_int py -. float_of_int t.h /. 2.0) *. t.scale in
  { Complex.re; im }
