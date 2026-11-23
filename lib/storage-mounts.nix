{ lib }:
areas:
let
  filesystems = lib.unique (lib.filter (mount: mount != null) (map (area: area.mount) areas));
  units = lib.unique (map (mount: mount.unit) filesystems);
  paths = lib.unique (map (area: area.location) areas);
in
{
  check = lib.concatMapStringsSep "\n" (mount: ''
    test "$(findmnt -n -o UUID --mountpoint ${lib.escapeShellArg mount.path})" = ${lib.escapeShellArg mount.uuid}
  '') filesystems;
  unitConfig = lib.concatStringsSep "\n" (
    [ "RequiresMountsFor=${lib.concatMapStringsSep " " builtins.toJSON paths}" ]
    ++ lib.optionals (units != [ ]) [
      "BindsTo=${lib.concatStringsSep " " units}"
      "After=${lib.concatStringsSep " " units}"
    ]
  );
}
