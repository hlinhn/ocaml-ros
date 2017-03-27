open Lwt
open RunNode
open Slave
       
let rec consume chan push =
  let open TypeInfo in
  Lwt_stream.get chan
  >>= (fun msg ->
    match msg with
    | None -> Lwt.return (Printf.printf "End\n%!")
    | Some m ->
       match m with
       | Bool b ->
          push (Some b);
          Lwt_unix.yield () >>= fun _ -> consume chan push)

let rec react pub bfrom =
  let open TypeInfo in
  Lwt_stream.get bfrom
  >>= (fun b ->
    match b with
    | None -> Lwt.return ()
    | Some obs ->
       let vel =
         if obs then { linear = { x = 0.; y = 0.; z = 0. };
                     angular = { x = -0.1; y = 0.; z = 0.5 }}
         else { linear = { x = 0.3; y = 0.; z = 0.};
                angular = {x = 0.; y = 0.; z = 0. }} in
       pub (Some (Twist vel));
       Lwt_unix.yield () >>= fun _ -> react pub bfrom)
        
let () =
  let (obs, pack) = Lwt_stream.create () in
  let (vel, pub) = Lwt_stream.create () in
  let mynode = initNode "Mynode" in
  let () = Printf.printf "%d\n" (Unix.getpid ()) in
  let (nnode, chan) = subscribe "/wall" "std_msgs/Bool" mynode in
  let (nnode, signal) = advertise vel pub "/cmd_vel_mux/input/teleop" "geometry_msgs/Twist" nnode in
  let () =
    match chan with
    | None -> ()
    | Some c ->
       let (run, cancel) = runLoop (fun () -> consume c pack) in
       let (run2, _) = runLoop (fun () -> react pub obs) in
       let () = run2 () in
       run () in
  ignore (runNode "Mynode" nnode)
         
         
