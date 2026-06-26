{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;
      perSystem =
        {
          lib,
          pkgs,
          ...
        }:
        let

          workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

          overlay = workspace.mkPyprojectOverlay {
            sourcePreference = "wheel";
          };

          editableOverlay = workspace.mkEditablePyprojectOverlay {
            root = "$REPO_ROOT";
          };

          pyprojectOverrides = _final: _prev: {
            # - https://pyproject-nix.github.io/uv2nix/FAQ.html
            # Implement build fixups here.
          };

          pythonSet =
            let
              python = pkgs.python3;
            in
            (pkgs.callPackage pyproject-nix.build.packages {
              inherit python;
            }).overrideScope
              (
                lib.composeManyExtensions [
                  pyproject-build-systems.overlays.wheel
                  overlay
                  pyprojectOverrides
                ]
              );

        in
        {
          packages.default = pythonSet.mkVirtualEnv "instawow" workspace.deps.default;

          devShells =
            let
              pythonSet' = pythonSet.overrideScope editableOverlay;
              python = pythonSet.python.interpreter;
              virtualenv = pythonSet'.mkVirtualEnv "instawow-dev-env" workspace.deps.all;
            in
            {
              default = pkgs.mkShell {
                packages = [
                  virtualenv
                  pkgs.uv
                ];

                env = {
                  # UV_NO_SYNC = "1";
                  UV_PYTHON = python;
                  UV_PYTHON_DOWNLOADS = "never";
                  LD_LIBRARY_PATH = lib.makeLibraryPath pkgs.pythonManylinuxPackages.manylinux1;
                };

                shellHook = ''
                  unset PYTHONPATH
                  export REPO_ROOT=$(git rev-parse --show-toplevel)
                '';
              };
            };
        };
    };
}
