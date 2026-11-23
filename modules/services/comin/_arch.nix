{
  pkgs,
  comin,
  hostname,
  repository,
  branch,
  storage,
}:
let
  inherit (pkgs) lib;
  cominConfig = pkgs.writeText "comin-${hostname}.json" (
    builtins.toJSON {
      inherit hostname;
      state_dir = storage.state.location;
      repository_type = "flake";
      exporter.listen_address = "127.0.0.1";
      grpc.unix_socket_mode = "0600";
      retention = {
        deployment_boot_entry_capacity = 5;
        deployment_successful_capacity = 5;
        deployment_any_capacity = 10;
      };
      build_confirmer.mode = "without";
      deploy_confirmer.mode = "without";
      remotes = [
        {
          name = "origin";
          url = repository;
          poller.period = 60;
          branches.main = {
            name = branch;
            operation = "switch";
          };
        }
      ];
    }
  );
  cominUnit = pkgs.writeTextDir "comin.service" ''
    [Unit]
    Description=Comin GitOps for ${hostname}
    Wants=network-online.target
    Requires=nix-daemon.socket
    After=network-online.target nix-daemon.socket

    [Service]
    Environment="PATH=/nix/var/nix/profiles/default/bin:/usr/bin"
    Environment="NIX_CONFIG=experimental-features = nix-command flakes"
    ExecStart=${lib.getExe comin} run --config ${cominConfig}
    Restart=always
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
  '';
in
cominUnit
