open Node.Node
open Tcp
open Lwt
open Slave
open RunNode
let makeSub tname msgLocation nname =
  let (channel, push) = Lwt_stream.create () in
  let (ttype, _) = TypeInfo.createTypeInfo msgLocation in
  let newsubs = { publishers = [];
                  subType = ttype;
                  add = subStream nname tname msgLocation push;
                  subStats = []; } in
  (newsubs, channel)

let subscribe tname msgLocation node =
  let subs_list = node.subscribe in
  if List.mem_assoc tname subs_list then (node, None)
  else
    if List.mem_assoc tname node.publish then (node, None)
    else
      let (newsubs, chan) = makeSub tname msgLocation node.nodeName in
      ({ node with subscribe = (tname, newsubs) :: node.subscribe },
       Some chan)
        
        
                                           
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
       
let () =
  let (nnode, chan) = subscribe "/chatter" "" mynode in
  let () =
    match chan with
    | None -> ()
    | Some c ->
       let (run, cancel) = runLoop (fun () -> consume c) in
       run () in
  ignore (runNode "Mynode" nnode)
