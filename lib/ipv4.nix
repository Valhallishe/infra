{ lib }:
{
  address = subnet: hostId:
    let
      parts = lib.splitString "/" subnet;
      octets = map lib.toInt (lib.splitString "." (builtins.head parts));
      prefix = lib.toInt (builtins.elemAt parts 1);
      pow = n: if n == 0 then 1 else 2 * pow (n - 1);
      size = pow (32 - prefix);
      base = lib.foldl' (acc: octet: acc * 256 + octet) 0 octets;
      value = base + hostId;
      mod = a: b: a - builtins.div a b * b;
    in
    assert lib.assertMsg (builtins.length octets == 4 && lib.all (x: x >= 0 && x <= 255) octets && prefix >= 0 && prefix <= 30) "infra.network.subnet must be an IPv4 CIDR with prefix 0..30";
    assert lib.assertMsg (mod base size == 0) "infra.network.subnet must be a network address";
    assert lib.assertMsg (hostId > 0 && hostId < size - 1) "Node hostId must fit the subnet and exclude network/broadcast addresses";
    lib.concatStringsSep "." (map (shift: toString (mod (builtins.div value (pow shift)) 256)) [ 24 16 8 0 ]);
}
