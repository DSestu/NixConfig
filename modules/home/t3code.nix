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

  # npm installs t3 into its own prefix here rather than being re-resolved by
  # `npx` on every start. Two reasons, both learned the hard way:
  #
  #   - `npx t3@latest` re-runs dependency resolution at each boot. The
  #     `@effect/*` packages declare peer ranges that send npm's resolver into
  #     near-unbounded backtracking — it burned 16+ minutes of CPU at 190%
  #     and still had not bound the port, so the funnel served a blank page.
  #     `--legacy-peer-deps` skips peer resolution and finishes in ~9s.
  #   - Keeping the install on disk means a boot with no network still starts
  #     the server from what is already there.
  runtimeDir = "${baseDir}/runtime";

  # The self-contained CLI payload for this machine. `t3` is only a launcher;
  # this is the package that actually carries the binary.
  t3Platform =
    {
      x86_64-linux = "@t3code/t3-linux-x64";
      aarch64-linux = "@t3code/t3-linux-arm64";
    }
    .${pkgs.stdenv.hostPlatform.system};

  # `t3@latest` re-resolves the newest release on every install — that is what
  # "latest" buys, at the cost of a network fetch and no reproducibility.
  # Pin `t3@<version>` here to freeze it.
  serveScript = pkgs.writeShellScript "t3code-serve" ''
    set -eu
    mkdir -p ${runtimeDir}
    cd ${runtimeDir}
    [ -f package.json ] || echo '{"name":"t3code-runtime","private":true}' > package.json

    # Best-effort refresh: a failed install (offline, registry down) must not
    # stop an already-installed server from starting.
    #
    # The payload is an optionalDependency of `t3`, and it pulls
    # @ff-labs/fff-bin-linux-x64-musl, which declares libc=musl and so fails
    # EBADPLATFORM on glibc. npm then silently drops the whole optional
    # subtree and the launcher aborts at startup with "no T3 Code CLI build is
    # available for this platform (linux-x64)". Naming the platform package as
    # a direct dependency with --force installs it anyway; --ignore-scripts
    # keeps node-pty from invoking node-gyp with no C toolchain on PATH (the
    # payload ships its own prebuilt).
    npm install --force --ignore-scripts --legacy-peer-deps --no-audit --no-fund \
      t3@latest ${t3Platform} || \
      echo "t3code: npm install failed, starting the existing install" >&2

    exec ./node_modules/.bin/t3 serve \
      --mode web \
      --host 127.0.0.1 \
      --port ${port} \
      --base-dir ${baseDir}
  '';

  # npm needs node; the agent shells out to git and a POSIX shell for its
  # provider CLIs, so keep those on PATH too. Not added to home.packages —
  # the units carry their own PATH.
  #
  # No C/Python toolchain here on purpose: npm's script-approval gate skips
  # the install scripts for node-pty and msgpackr-extract, and the server runs
  # fine on the prebuilt paths. If PTY features ever misbehave, that is the
  # thread to pull — add python3/gcc/gnumake and approve the scripts.
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
