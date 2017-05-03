open RunNode

let rec consume chan =
  Lwt_stream.get chan
  >>= (fun msg ->
    match msg with
    | None -> Lwt.return (Printf.printf "End\n%!")
    | Some m -> Printf.printf "%s\n%!" m;
                consume chan)
        
let () =
  let mynode = initNode "Mynode" in
  let (nnode, chan) = subscribe "/wall" "std_msgs/Bool" mynode in
  let () =
    match chan with
    | None -> ()
    | Some c ->
       let (run, cancel) = runLoop (fun () -> consume c) in
       run () in
  ignore (runNode "Mynode" nnode)
       
