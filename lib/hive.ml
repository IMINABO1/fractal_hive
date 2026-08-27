(* The parallel auction. N Domain workers pull tiles from one shared, bid-ordered
   queue -- which here is a bid-sorted array plus an atomic cursor, so claiming the
   next tile is a lock-free fetch-and-add and a lower index means a higher bid.
   Rendering is independent per tile (disjoint pixels), so nothing about the render
   needs locking; only [emit] does, and the caller serializes that. [emit] returns
   false once the client has gone, which flips a shared flag so workers stop. *)

let render ~vp ~max_iter ~size ~workers ~emit =
  let tiles = Tile.split ~w:vp.Viewport.w ~h:vp.Viewport.h ~size in
  let planned = Array.of_list (Auction.plan ~vp ~max_iter tiles) in
  let n = Array.length planned in
  let cursor = Atomic.make 0 in
  let aborted = Atomic.make false in
  let worker () =
    let rec loop () =
      if not (Atomic.get aborted) then begin
        let i = Atomic.fetch_and_add cursor 1 in
        if i < n then begin
          let tile, _bid = planned.(i) in
          let bytes = Render.render_tile ~vp ~max_iter tile in
          if not (emit tile bytes) then Atomic.set aborted true;
          loop ()
        end
      end
    in
    loop ()
  in
  List.init workers (fun _ -> Domain.spawn worker) |> List.iter Domain.join
