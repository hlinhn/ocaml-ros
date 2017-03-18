
let createTypeInfo msgLocation =
  ("std_msgs/String", "992ce8a1687cec8c8bd883ec73ca41d1")
    
let formatType msgLocation m =
  let open RosHeader in
  let mainstr = taglen m in
  taglen mainstr
