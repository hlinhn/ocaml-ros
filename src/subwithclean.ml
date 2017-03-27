open Node.Node
open Tcp
open Lwt
open Slave
open RunNode
       
                                           
let mynode = { nodeName = "Mynode";
               master = "http://localhost:11311";
               nodeUri = "";
               signalShutdown = Lwt_switch.create();
               subscribe = [];
               publish = [];
             }
               
let rec consume chan =
  Lwt_stream.get chan
  >>= (fun msg ->
    match msg with
    | None -> Lwt.return (Printf.printf "End\n%!")
    | Some m -> Printf.printf "%s\n%!" m;
                consume chan)

let rec feed push n =
  let msg = String.concat " " ["Hello World"; Pervasives.string_of_int n] in
  Lwt.return (push (Some msg)) >>=
    (fun _ -> Lwt_unix.yield ()) >>=
    (fun _ -> feed push (n + 1))
        
(*let () =
  let (nnode, chan) = subscribe "/chatter" "" mynode in
  let () =
    match chan with
    | None -> ()
    | Some c ->
       let (run, cancel) = runLoop (fun () -> consume c) in
       run () in
  ignore (runNode "Mynode" nnode)
 *)

let () =
  let (nnode, chan) = subscribe "/chatter" "" mynode in
  let (chan2, push2) = Lwt_stream.create () in
  let (nnode, waitsig2) = advertise chan2 push2 "/chatter2" "" nnode in
  let () =
    match chan with
    | None -> ()
    | Some c ->
       let (run, cancel) = runLoop (fun () -> consume c) in
       let (run2, _) = runLoop (fun () -> feed push2 0) in
       let () = run2 () in
       run () in
  ignore (runNode "Mynode" nnode)
