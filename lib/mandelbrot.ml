(* Escape-time: iterate z <- z^2 + c from z = 0 until |z| > 2 (norm2 > 4) or we
   hit max_iter. Returns the iteration count; max_iter means "did not escape". *)
let escape ~max_iter (c : Complex.t) =
  let rec loop z i =
    if i >= max_iter then max_iter
    else
      let z' = Complex.add (Complex.mul z z) c in
      if Complex.norm2 z' > 4.0 then i else loop z' (i + 1)
  in
  loop Complex.zero 0
