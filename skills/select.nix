# Evaluate enabled.nix into { installedName = "available/relative/path"; }.
# New NixOS hosts install these paths directly; legacy staging reconstructs
# links only inside private .deployment/. "family/*" walks reviewed source
# recursively. Reject missing skills and duplicate installed names at eval.
let
  source = ./available;
  entries = import ./enabled.nix;
  valid = path: builtins.match "[a-zA-Z0-9_/-]+" path != null;
  skill = relative:
    assert valid relative;
    assert builtins.pathExists (source + "/${relative}/SKILL.md");
    { name = builtins.baseNameOf relative; value = relative; };
  # A trailing /* means every skill below that directory, recursively. It is
  # expanded from reviewed source at evaluation time, never by the shell.
  walk = relative:
    let dir = source + "/${relative}";
        children = builtins.readDir dir;
    in builtins.concatLists (map (name:
      let next = "${relative}/${name}";
      in if children.${name} != "directory" then []
         else if builtins.pathExists (source + "/${next}/SKILL.md") then [ (skill next) ]
         else walk next
    ) (builtins.attrNames children));
  expand = entry:
    assert builtins.isString entry;
    let length = builtins.stringLength entry;
        wildcard = length > 2 && builtins.substring (length - 2) 2 entry == "/*";
        prefix = if wildcard then builtins.substring 0 (length - 2) entry else entry;
    in assert valid prefix;
       if wildcard then walk prefix else [ (skill prefix) ];
  selected = builtins.concatLists (map expand entries);
  result = builtins.listToAttrs selected;
in assert builtins.isList entries;
   assert builtins.length selected == builtins.length (builtins.attrNames result);
   result
