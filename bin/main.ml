let () =
  let port = ref 8080 in
  let iters = ref 200 in
  let webroot = ref "web" in
  let spec =
    [ ("--port", Arg.Set_int port, "port to listen on (default 8080)");
      ("--iters", Arg.Set_int iters, "max escape iterations (default 200)");
      ("--webroot", Arg.Set_string webroot, "directory holding index.html (default web)") ]
  in
  Arg.parse spec (fun _ -> ()) "fractalhive [--port N] [--iters N] [--webroot DIR]";
  Server.start ~port:!port ~webroot:!webroot ~max_iter:!iters
