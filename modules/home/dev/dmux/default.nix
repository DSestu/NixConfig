{
  lib,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  jq,
  tmux,
  git,
}:
# dmux is a tmux/git-worktree multiplexer for coding agents. It is not in
# nixpkgs, so we build straight from the npm tarball (which already ships
# the compiled dist/ tree — no TypeScript build needed).
#
# npm's published tarball carries no lockfile, so package-lock.json here is
# generated once from dmux's runtime `dependencies` only:
#   npm install --package-lock-only
# Regenerate it (and both hashes) on every version bump.
buildNpmPackage (finalAttrs: {
  pname = "dmux";
  version = "5.10.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/dmux/-/dmux-${finalAttrs.version}.tgz";
    hash = "sha256-meJvjTlzA7Ym/Pj6JkfqJXJQa5iWAVrKk+19bGs+xzM=";
  };

  # dmux types its pane-bootstrap command into the new pane with `tmux
  # send-keys`, in POSIX sh syntax (`VAR=$?`, `if ...; then ... fi`, `||`).
  # fish rejects all three, so with fish as the pane shell the agent never
  # launches. The patch adds a fish branch, picked at runtime off $SHELL.
  # Upstream has no shell-detection here — re-check on every version bump.
  # dmux installs its `client-resized` tmux hook with a *blocking* `run-shell`
  # (no `-b`), unlike every other hook it installs. tmux forks a shell per
  # resize event and stalls its command queue while it runs; dmux answers each
  # signal with `resize-window` + `select-layout`, which emits another
  # `client-resized`. Dragging a window edge therefore wedges the whole tmux
  # server — every client on that socket, dmux or not, stops accepting input.
  # The patch adds `-b` at the three sites that set the hook.
  patches = [
    ./fish-pane-bootstrap.patch
    ./resize-hook-nonblocking.patch
  ];

  # The lockfile covers runtime deps only, so devDependencies must go too —
  # otherwise `npm ci` decides the lock is out of sync with package.json and
  # tries to hit the network from inside the sandbox (ENOTCACHED).
  #
  # jq is referenced by absolute store path: postPatch also runs inside the
  # fixed-output npm-deps derivation, which does not inherit nativeBuildInputs.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    ${lib.getExe jq} 'del(.devDependencies)' package.json > package.json.new
    mv package.json.new package.json
  '';

  npmDepsHash = "sha256-EW79zn5jsNgLqUa2ClkdF4N+uWkY3/rnq+ZVMl52Sf4=";

  # dist/ is prebuilt; the package's own `prepack` hook builds a macOS helper
  # bundle and would fail here, hence --ignore-scripts on both steps.
  dontNpmBuild = true;
  npmFlags = ["--ignore-scripts"];
  npmPackFlags = ["--ignore-scripts"];

  nativeBuildInputs = [makeWrapper jq];

  # dmux shells out to tmux for every pane operation and to git for worktrees.
  postInstall = ''
    wrapProgram $out/bin/dmux \
      --prefix PATH : ${lib.makeBinPath [tmux git]}
  '';

  meta = {
    description = "Tmux pane manager with AI agent integration for parallel development workflows";
    homepage = "https://github.com/standardagents/dmux";
    license = lib.licenses.mit;
    mainProgram = "dmux";
    platforms = lib.platforms.unix;
  };
})
