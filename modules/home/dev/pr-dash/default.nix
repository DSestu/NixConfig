{
  lib,
  buildGoModule,
}:
# pr-dash: PR dashboard TUI for the `ws` workspace. Spec in ./SPEC.md.
buildGoModule {
  pname = "pr-dash";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./go.sum
      (lib.fileset.fileFilter (f: f.hasExt "go" || f.hasExt "graphql" || f.hasExt "json") ./.)
    ];
  };

  vendorHash = "sha256-85FWE35f/z1c4PDysbIkC70olHizmhTfKsPhyatGCGk=";

  ldflags = ["-s" "-w" "-X main.version=0.1.0"];

  meta.mainProgram = "pr-dash";
}
