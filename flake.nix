{
  description = "Reusable GitHub Actions shared across GenLayer repositories";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # No `packages.default`: this repo ships YAML that GitHub interprets, there is
  # nothing to build. The flake exists for the hooks and the dev shell.
  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      forEachSystem = lib.genAttrs (import inputs.systems);
    in
    {
      formatter = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          config = self.checks.${system}.pre-commit-check.config;
          inherit (config) package configFile;
        in
        pkgs.writeShellScriptBin "pre-commit-run" ''
          ${pkgs.lib.getExe package} run --all-files --config ${configFile}
        ''
      );

      checks = forEachSystem (system: {
        pre-commit-check = inputs.git-hooks.lib.${system}.run {
          src = ./.;
          hooks =
            let
              pkgs = import nixpkgs { inherit system; };
            in
            {
              check-commit-message = {
                enable = true;
                name = "check commit message";
                description = "Validate the commit message against conventional-commit rules.";
                entry = "${pkgs.python3}/bin/python3 ${./support/scripts/check-commit-message.py} --message-file";
                language = "system";
                stages = [ "commit-msg" ];
              };

              nixfmt.enable = true;

              actionlint.enable = true;

              # `check-yaml` parses; it does not know the action schema. It
              # still catches the failure mode that actually happens here — an
              # unquoted `on:` or a botched block scalar in a long description.
              check-yaml.enable = true;

              prettier = {
                enable = true;
                files = "\\.(json|md|markdown|ya?ml)$";
              };
            };
        };
      });

      devShells = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          inherit (self.checks.${system}.pre-commit-check) shellHook enabledPackages;
        in
        {
          default = pkgs.mkShell {
            inherit shellHook;
            buildInputs = enabledPackages ++ [ pkgs.actionlint ];
          };
        }
      );
    };
}
