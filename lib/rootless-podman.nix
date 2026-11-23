{ pkgs, name, uid, subId, home, runtime, registryRepository }:
let
  account = "oci-${name}";
  policy = pkgs.writeText "podman-pinned-image-policy.json" (builtins.toJSON {
    default = [{ type = "reject"; }];
    transports.docker.${registryRepository} = [{ type = "insecureAcceptAnything"; }];
  });
  setup = pkgs.writeShellScript "${name}-podman-account" ''
    set -euo pipefail
    export PATH=/usr/bin
    if ! getent passwd "${account}" >/dev/null; then
      groupadd --gid ${toString uid} ${account}
      useradd --system --uid ${toString uid} --gid ${account} --home-dir ${home} --shell /usr/bin/nologin ${account}
    fi
    test "$(id -u ${account}):$(id -g ${account})" = "${toString uid}:${toString uid}"
    for mapping in /etc/subuid /etc/subgid; do
      if ! grep -Fxq '${account}:${toString subId}:65536' "$mapping"; then
        case "$mapping" in
          /etc/subuid) usermod --add-subuids ${toString subId}-${toString (subId + 65535)} ${account} ;;
          /etc/subgid) usermod --add-subgids ${toString subId}-${toString (subId + 65535)} ${account} ;;
        esac
      fi
    done
    install -d -m0700 -o ${account} -g ${account} ${home} ${runtime}/user
    install -d -m0700 -o ${account} -g ${account} ${home}/.config ${home}/.config/containers
    install -m0600 -o ${account} -g ${account} ${policy} ${home}/.config/containers/policy.json
  '';
  podman = pkgs.writeShellScript "${name}-podman" ''
    set -eu
    export PATH=/usr/bin:$PATH
    export HOME=${home}
    export XDG_RUNTIME_DIR=${runtime}/user
    exec ${pkgs.podman}/bin/podman --cgroup-manager=cgroupfs "$@"
  '';
in
{ inherit account setup podman; }
