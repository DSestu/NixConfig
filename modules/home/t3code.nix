# T3 Code (https://github.com/pingdotgg/t3code) as a systemd *user* service,
# bound to loopback and reached from elsewhere through T3 Connect.
#
# Home Manager only — no NixOS system-unit branch. Because home.nix is part
# of `commonHomeImports`, every NixOS profile picks this up as a user unit
# too; on a headless profile that means lingering has to be on for the unit
# to start without a login (`users.users.david.linger = true`).
#
# The package comes from nixpkgs (`pkgs.t3code`), which is the whole point of
# this module being short. Earlier revisions ran `npm install t3@latest` on
# every start into a scratch prefix; that fought npm's peer resolver, needed
# `--force` to get the platform payload past an EBADPLATFORM on glibc, and
# still crash-looped with "no T3 Code CLI build is available for this
# platform". None of that survives: the nixpkgs derivation builds the server
# from source and wraps it with the agent CLIs on PATH.
#
# Upstream also ships its own service installer (`t3 service install`), which
# writes ~/.config/systemd/user/t3code.service and self-updates the runtime
# under ~/.t3/runtime/versions. That is the thing this module replaces — run
# `t3 service uninstall` once, or the two fight over the port.
#
# Caveats worth knowing before you use the URL:
#   - No authentication is *available* to switch off: T3 Code always requires
#     a device pairing token. Mint one with `t3 pair`.
#   - Remote access is T3 Connect (`t3 connect link`), not a Tailscale funnel.
#     Funnel is a paid-plan feature and returned "Funnel is not available on
#     the Starter plan" on this tailnet, so the funnel unit is gone. T3
#     Connect relays through relay.t3.codes and fetches its own cloudflared
#     into ~/.t3/tools at runtime — that part stays outside Nix.
{
  config,
  pkgs,
  ...
}: let
  port = "3773";

  # ~/.t3 is upstream's own default (T3CODE_HOME), and it is where the T3
  # Connect authorization, relay link and downloaded cloudflared already sit.
  # Whitelisted for impermanence in modules/home/persistence.nix.
  baseDir = "${config.home.homeDirectory}/.t3";

  # enableClaude is off by default upstream; this machine drives T3 Code with
  # Claude Code, so put it on the server's PATH. git/gh/codex are already on
  # by the package's own defaults.
  t3 = pkgs.t3code.override {enableClaude = true;};
in {
  # `t3` was not on PATH at all before — pairing meant typing the full path
  # into a versioned node_modules directory.
  home.packages = [t3];

  systemd.user.services.t3code-serve = {
    Unit.Description = "T3 Code server (loopback)";
    Service = {
      ExecStart = "${t3}/bin/t3 serve --mode web --host 127.0.0.1 --port ${port} --base-dir ${baseDir}";
      Environment = [
        # The CLI reads T3CODE_HOME too; keep both in agreement so a manual
        # `t3 pair` from a shell talks to the same state as the unit.
        "T3CODE_HOME=${baseDir}"

        # T3 Connect's relay is a cloudflared tunnel that the server spawns as
        # a child, so it inherits this. cloudflared prefers QUIC on UDP 7844;
        # egress to that port is dropped on this network, which left it
        # looping on "failed to dial to edge with quic: timeout: no recent
        # network activity" and the machine never showed up as connected.
        # http2 carries the same tunnel over TCP 443 instead.
        "TUNNEL_TRANSPORT_PROTOCOL=http2"
      ];
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = ["default.target"];
  };
}
