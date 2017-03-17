                         
module Node = struct
  type uri = string
  type topic = Topic : 'a Lwt_stream.t -> topic
  type publishStats = { byteSent : int;
                        numSent : int;
                        pubConnected : bool;
                      }
                          
  type publication = { mutable subscribers : uri list;
                       mutable subAddr : Lwt_unix.file_descr list;
                       pubType : string;
                       pubPort : int;
                       pubTopic : topic;
                       mutable pubStats: (uri * publishStats) list;
                     }
                       
  type subscribeStats = { byteReceived : int;
                          subConnected : bool;
                        }

  type subscription = { mutable publishers : uri list;
                        subType : string;
                        add : uri -> unit Lwt.t;
                        mutable subStats : (uri * subscribeStats) list;
                      }
                        
  type nodeStat = { nodeName : string;
                    master : uri;
                    nodeUri : uri;
                    subscribe : (string * subscription) list;
                    publish : (string * publication) list;
                  }
                    
  let startUpNode = { nodeName = "";
                      master = "";
                      nodeUri = "";
                      subscribe = [];
                      publish = []; }

  let startUpSub = { publishers = [];
                     subType = "";
                     add = (fun x -> Lwt.return (Printf.printf "%s\n%!" x));
                     subStats = [];
                   }

  let startUpPub = { subscribers = [];
                     subAddr = [];
                     pubType = "";
                     pubPort = -1;
                     pubTopic = Topic (fst (Lwt_stream.create ()));
                     pubStats = [];
                   }
                     
  let getPublications n =
    let formatPub (name, p) = (name, p.pubType, p.pubStats) in
    List.map formatPub n.publish

  let getSubscriptions n =
    let formatSub (name, s) = (name, s.subType, s.subStats) in
    List.map formatSub n.subscribe

  let addConnection (acc, ls) u =
    if (List.mem u ls) then (acc, ls)
    else
      let ls' = u :: ls in
      (u :: acc, ls')
        
  let publisherUpdate n name u =
    if (not (List.mem_assoc name (n.subscribe))) then (fun () -> [()])
    else
      let s = List.assoc name (n.subscribe) in
      let p = s.publishers in
      let (acc, updated) = List.fold_left addConnection ([], p) u in
      let () = s.publishers <- updated in
      let aggregate = fun () -> List.map (fun t -> Lwt.async (fun () -> s.add t)) acc in
      aggregate

  let getPort n name =
    if (not (List.mem_assoc name (n.publish))) then None
    else
      let p = List.assoc name (n.publish) in
      Some p.pubPort
end
