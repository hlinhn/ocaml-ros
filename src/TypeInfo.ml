

type vector3 = { x : float; y : float; z: float } 
type twist = { linear : vector3; angular : vector3 }
               
type rosmsg =
  | String of string
  | Bool of bool
  | Vector3 of vector3
  | Twist of twist
              
let createTypeInfo = function
  | "std_msgs/String" ->
     ("std_msgs/String", "992ce8a1687cec8c8bd883ec73ca41d1")
  | "std_msgs/Bool" ->
     ("std_msgs/Bool", "8b94c1b53db61fb6aed406028ad6332a")
  | "geometry_msgs/Twist" ->
     ("geometry_msgs/Twist", "9f195f881246fdfa2798d1d3eebca84a")
  | _ -> ("", "")
           
let formatType msgLocation m =
  let open Core_kernel in
  let open RosHeader in
  match msgLocation with
  | "std_msgs/String" ->
     begin
       match m with
       | String msg_string -> let mainstr = taglen msg_string in taglen mainstr
       | _ -> raise (Failure "Actual message type and declared message type unmatched")
     end
  | "geometry_msgs/Twist" ->
     begin
       match m with
       | Twist t -> let str1 = Bytes.create 24 in
                    let str2 = Bytes.create 24 in
                    let createMap t = ([(t.linear.x, 0); (t.linear.y, 1); (t.linear.z, 2)], [(t.angular.x, 0); (t.angular.y, 1); (t.angular.z, 2)]) in
                    let (t1, t2) = createMap t in
                    let _ = List.map (fun (x, p) -> Binary_packing.pack_float ~byte_order:`Little_endian ~buf:str1 ~pos:(p*8) x) t1 in
                    let _ = List.map (fun (x, p) -> Binary_packing.pack_float ~byte_order:`Little_endian ~buf:str2 ~pos:(p*8) x) t2 in
                    let str = String.concat "" [str1; str2] in
                    taglen str
       | _ -> raise (Failure "Actual message type and declared message type unmatched")
     end
  | _ -> raise (Failure "Unhandled case")
        

let unpackType = function
  | "std_msgs/String" -> (fun m -> let msglen = BatInt32.to_int (BatInt32.unpack (Bytes.sub m 0 4) 0) in
                                   let msg = Bytes.sub m 4 ((Bytes.length m) - 4) in
                                   String msg)
  | "std_msgs/Bool" -> (fun m -> if int_of_char (Bytes.get m 0) == 0 then (Bool false) else (Bool true))
  | _ -> (fun m -> String m)
  
