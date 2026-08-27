(* v3: the sharded auction. The image is split into k "markets" (vertical bands),
   each with its own bid-ordered queue and atomic cursor; every worker has a home
   market. With arbitrage off, a worker serves only its home and then idles -- so
   a light market's workers sit unused while a heavy market starves. With arbitrage
   on, a worker whose home has drained steals the highest-bidding tile from any
   market, which re-globalizes the auction (this is why one global market beats
   silos). Per-worker render time is recorded -- each worker writes only its own
   slot, so no lock -- to compare utilization between the two modes. With markets=1
   this reduces to the v2 global auction. *)

type market = {
  queue : (Tile.t * float) array; (* bid-sorted descending *)
  cursor : int Atomic.t;
}

type stats = {
  wall_ms : float;
  util : float array; (* per worker: render time / wall time *)
  tiles : int array; (* per worker: tiles rendered *)
  markets : int;
}

let market_hue m k =
  let t = float_of_int m /. float_of_int (max 1 k) in
  let ch phase = int_of_float (128.0 +. 127.0 *. sin (6.2832 *. (t +. phase))) in
  (ch 0.0, ch 0.33, ch 0.66)

(* Blend a flat hue into the tile's RGBA so the market bands are visible. *)
let tint_tile bytes (r, g, b) =
  let a = 0.15 in
  let blend i v =
    let c = float_of_int (Char.code (Bytes.get bytes i)) in
    Bytes.set bytes i (Char.chr (int_of_float (c *. (1.0 -. a) +. float_of_int v *. a)))
  in
  let n = Bytes.length bytes in
  let i = ref 0 in
  while !i < n do
    blend !i r; blend (!i + 1) g; blend (!i + 2) b;
    i := !i + 4
  done

let run ~vp ~max_iter ~size ~workers ~markets ~arbitrage ~tint ~partition ~emit =
  let k = max 1 (min markets workers) in
  let w = vp.Viewport.w in
  let planned = Auction.plan ~vp ~max_iter (Tile.split ~w ~h:vp.Viewport.h ~size) in
  (* "band" gives each market a contiguous vertical slice (boundary concentrates in a
     couple of markets); "strided" interleaves columns so every market gets a mix of
     hot and cold tiles -- the fair partition to test the arbitrage win against. *)
  let market_of (t, _) =
    match partition with
    | "strided" -> t.Tile.x0 / size mod k
    | _ -> min (k - 1) ((t.Tile.x0 + t.Tile.x1) / 2 * k / w)
  in
  let mkts =
    Array.init k (fun m ->
        { queue = Array.of_list (List.filter (fun tb -> market_of tb = m) planned);
          cursor = Atomic.make 0 })
  in
  let aborted = Atomic.make false in
  let busy = Array.make workers 0.0 in
  let tiles = Array.make workers 0 in
  let claim m =
    let i = Atomic.fetch_and_add mkts.(m).cursor 1 in
    if i < Array.length mkts.(m).queue then Some mkts.(m).queue.(i) else None
  in
  let rec steal () =
    let best = ref (-1) and best_bid = ref neg_infinity in
    for m = 0 to k - 1 do
      let c = Atomic.get mkts.(m).cursor in
      if c < Array.length mkts.(m).queue then begin
        let _, bid = mkts.(m).queue.(c) in
        if bid > !best_bid then (best_bid := bid; best := m)
      end
    done;
    if !best < 0 then None
    else match claim !best with Some _ as r -> r | None -> steal ()
  in
  let worker id =
    let home = id mod k in
    let rec loop () =
      if not (Atomic.get aborted) then
        let next =
          match claim home with
          | Some _ as r -> r
          | None -> if arbitrage then steal () else None
        in
        match next with
        | None -> ()
        | Some (tile, _bid) ->
          let t0 = Unix.gettimeofday () in
          let bytes = Render.render_tile ~vp ~max_iter tile in
          busy.(id) <- busy.(id) +. (Unix.gettimeofday () -. t0);
          if tint then tint_tile bytes (market_hue (market_of (tile, 0.0)) k);
          tiles.(id) <- tiles.(id) + 1;
          if not (emit tile bytes) then Atomic.set aborted true;
          loop ()
    in
    loop ()
  in
  let t_start = Unix.gettimeofday () in
  List.init workers (fun i -> Domain.spawn (fun () -> worker i)) |> List.iter Domain.join;
  let wall = Unix.gettimeofday () -. t_start in
  { wall_ms = wall *. 1000.0;
    util = Array.map (fun b -> if wall > 0.0 then b /. wall else 0.0) busy;
    tiles;
    markets = k }
