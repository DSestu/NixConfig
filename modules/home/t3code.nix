# T3 Code (https://github.com/pingdotgg/t3code) as a systemd *user*
# service, published to the public internet through a Tailscale funnel.
#
# Two units, so a funnel failure never takes the server down with it:
#
#   t3code-serve   `npx t3@latest serve` bound to 127.0.0.1:3773
#   t3code-funnel  `tailscale funnel` fronting that port on public HTTPS :443
#
# Home Manager only — no NixOS system-unit branch. Because home.nix is part
# of `commonHomeImports`, every NixOS profile picks this up as a user unit
# too; on a headless profile that means lingering has to be on for the units
# to start without a login (`users.users.david.linger = true`).
#
# Caveats worth knowing before you use the URL:
#   - No authentication is *available* to switch off: T3 Code always
#     requires a device pairing token. Read it from the unit's journal
#     (`journalctl --user -u t3code-serve`) or mint a fresh one with
#     `npx t3@latest pair`. The funnel itself is wide open — anyone with
#     the URL reaches the pairing screen of an agent that can run shell
#     commands in your projects.
#   - The funnel needs HTTPS certs + the `funnel` node attribute enabled in
#     the tailnet ACLs, and a machine already logged in to the tailnet.
#   - Driving `tailscale funnel` from a user unit needs
#     `sudo tailscale set --operator=david` once; otherwise the funnel unit
#     exits with a permission error and only the loopback server runs.
{
  config,
  pkgs,
  ...
}: let
  port = "3773";
  # Explicit data dir so the state location is deterministic and can be
  # whitelisted for impermanence (modules/home/persistence.nix).
  baseDir = "${config.home.homeDirectory}/.local/share/t3code";

  # `t3@latest` re-resolves the newest release on every start — that is what
  # "latest" buys, at the cost of a network fetch at boot and no
  # reproducibility. Pin `t3@<version>` here to freeze it.
  serveScript = pkgs.writeShellScript "t3code-serve" ''
    exec npx --yes t3@latest serve \
      --mode web \
      --host 127.0.0.1 \
      --port ${port} \
      --base-dir ${baseDir}
  '';

  # npx needs node; the agent shells out to git and a POSIX shell for its
  # provider CLIs, so keep those on PATH too. Not added to home.packages —
  # the units carry their own PATH.
  runtimePath = [pkgs.nodejs_24 pkgs.git pkgs.bash pkgs.coreutils];

  # Tailscale funnel only accepts 443 / 8443 / 10000 as the public port;
  # 443 keeps the URL clean. `--yes` skips the interactive confirmation,
  # `--bg` hands the mapping to tailscaled instead of blocking.
  funnelStart = "${pkgs.tailscale}/bin/tailscale funnel --bg --yes ${port}";
  funnelStop = "${pkgs.tailscale}/bin/tailscale funnel --https=443 off";
in {
  systemd.user.services.t3code-serve = {
    Unit.Description = "T3 Code server (loopback)";
    Service = {
      ExecStart = "${serveScript}";
      Environment = ["PATH=${pkgs.lib.makeBinPath runtimePath}"];
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = ["default.target"];
  };

  systemd.user.services.t3code-funnel = {
    Unit = {
      Description = "Public HTTPS funnel for the T3 Code server";
      After = ["t3code-serve.service"];
      Wants = ["t3code-serve.service"];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      # No Restart= — systemd rejects it on Type=oneshot.
      ExecStart = funnelStart;
      ExecStop = funnelStop;
    };
    Install.WantedBy = ["default.target"];
  };
}
