(* A minimal HTTP/1.1 server over stdlib Unix sockets. It is the "hive": the
   browser asks it for a bid-ordered plan and then for each tile's pixels.
   Serial (one request at a time) in v1 -- parallelism is the v2 upgrade. *)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

(* First index of [sub] in [s], if any. *)
let find_sub s sub =
  let ls = String.length s and lsub = String.length sub in
  let rec go i =
    if i + lsub > ls then None
    else if String.sub s i lsub = sub then Some i
    else go (i + 1)
  in
  go 0

(* Read from [fd] until the end of the HTTP headers (GET has no body). *)
let read_headers fd =
  let buf = Buffer.create 1024 in
  let chunk = Bytes.create 4096 in
  let rec loop () =
    match find_sub (Buffer.contents buf) "\r\n\r\n" with
    | Some _ -> Buffer.contents buf
    | None ->
      let n = Unix.read fd chunk 0 4096 in
      if n = 0 then Buffer.contents buf
      else (Buffer.add_subbytes buf chunk 0 n; loop ())
  in
  loop ()

(* "GET /path?query HTTP/1.1" -> "/path?query" *)
let request_target req =
  let line =
    match String.index_opt req '\r' with
    | Some i -> String.sub req 0 i
    | None -> req
  in
  match String.split_on_char ' ' line with
  | _method :: target :: _ -> target
  | _ -> "/"

let split_query target =
  match String.index_opt target '?' with
  | Some i ->
    (String.sub target 0 i,
     String.sub target (i + 1) (String.length target - i - 1))
  | None -> (target, "")

let parse_query q =
  if q = "" then []
  else
    String.split_on_char '&' q
    |> List.filter_map (fun kv ->
           match String.index_opt kv '=' with
           | Some i ->
             Some (String.sub kv 0 i,
                   String.sub kv (i + 1) (String.length kv - i - 1))
           | None -> None)

let qfloat p k default =
  match List.assoc_opt k p with
  | Some v -> (try float_of_string v with _ -> default)
  | None -> default

let qint p k default =
  match List.assoc_opt k p with
  | Some v -> (try int_of_string v with _ -> default)
  | None -> default

let send_all fd s =
  let b = Bytes.of_string s in
  let len = Bytes.length b in
  let rec go off = if off < len then go (off + Unix.write fd b off (len - off)) in
  go 0

let respond fd ~status ~content_type ~body =
  send_all fd
    (Printf.sprintf
       "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
       status content_type (String.length body));
  send_all fd body

let viewport_of_params p =
  Viewport.make
    ~cx:(qfloat p "cx" (-0.5))
    ~cy:(qfloat p "cy" 0.0)
    ~scale:(qfloat p "scale" 0.005)
    ~w:(qint p "w" 800)
    ~h:(qint p "h" 600)

let tile_of_params p : Tile.t =
  { x0 = qint p "x0" 0; y0 = qint p "y0" 0; x1 = qint p "x1" 0; y1 = qint p "y1" 0 }

let json_of_plan planned =
  let buf = Buffer.create 4096 in
  Buffer.add_char buf '[';
  List.iteri
    (fun i ((t : Tile.t), bid) ->
      if i > 0 then Buffer.add_char buf ',';
      Buffer.add_string buf
        (Printf.sprintf {|{"x0":%d,"y0":%d,"x1":%d,"y1":%d,"bid":%g}|}
           t.x0 t.y0 t.x1 t.y1 bid))
    planned;
  Buffer.add_char buf ']';
  Buffer.contents buf

let handle_conn ~webroot ~max_iter fd =
  (try
     let params_of req = parse_query (snd (split_query (request_target req))) in
     let path_of req = fst (split_query (request_target req)) in
     let req = read_headers fd in
     let path = path_of req and params = params_of req in
     match path with
     | "/" | "/index.html" ->
       respond fd ~status:"200 OK"
         ~content_type:"text/html; charset=utf-8"
         ~body:(read_file (Filename.concat webroot "index.html"))
     | "/plan" ->
       let vp = viewport_of_params params in
       let tiles = Tile.split ~w:vp.Viewport.w ~h:vp.Viewport.h ~size:(qint params "tile" 64) in
       respond fd ~status:"200 OK" ~content_type:"application/json"
         ~body:(json_of_plan (Auction.plan ~vp ~max_iter tiles))
     | "/tile" ->
       let vp = viewport_of_params params in
       let bytes = Render.render_tile ~vp ~max_iter (tile_of_params params) in
       respond fd ~status:"200 OK" ~content_type:"application/octet-stream"
         ~body:(Bytes.to_string bytes)
     | _ -> respond fd ~status:"404 Not Found" ~content_type:"text/plain" ~body:"not found"
   with e ->
     (try
        respond fd ~status:"500 Internal Server Error" ~content_type:"text/plain"
          ~body:(Printexc.to_string e)
      with _ -> ()));
  (try Unix.close fd with _ -> ())

let start ~port ~webroot ~max_iter =
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  Unix.listen sock 16;
  Printf.printf "FractalHive listening on http://localhost:%d  (webroot=%s, iters=%d)\n%!"
    port webroot max_iter;
  while true do
    let fd, _ = Unix.accept sock in
    handle_conn ~webroot ~max_iter fd
  done
