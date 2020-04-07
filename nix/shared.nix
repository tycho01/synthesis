{ compiler ? "ghc865" }:

let
  haskTorchSrc = builtins.fetchGit {
    url = https://github.com/hasktorch/hasktorch;
    rev = "86aa86799a2f6927b5278b3b88ca94c9ec31da0d";
    ref = "master";
  };

  hasktorchOverlay = (import (haskTorchSrc + "/nix/shared.nix") { compiler = "ghc865"; }).overlayShared;

  synthesisOverlay = pkgsNew: pkgsOld: {
    haskell = pkgsOld.haskell // {
      packages = pkgsOld.haskell.packages // {
        "${compiler}" = pkgsOld.haskell.packages."${compiler}".override (old: {
            overrides =
              let
                mkSynthesisExtension = postfix:
                  haskellPackagesNew: haskellPackagesOld: {
                    "synthesis_${postfix}" =
                      (haskellPackagesOld.callCabal2nix
                        "synthesis"
                        ../.
                        { hasktorch    = haskellPackagesNew.   "hasktorch_${postfix}"
                        ; libtorch-ffi = haskellPackagesNew."libtorch-ffi_${postfix}"
                        ; }
                      );
                  };

              in
                pkgsNew.lib.fold
                  pkgsNew.lib.composeExtensions
                  (old.overrides or (_: _: {}))
                  [ (mkSynthesisExtension "cpu")
                    (mkSynthesisExtension "cudatoolkit_9_2")
                    (mkSynthesisExtension "cudatoolkit_10_1")
                  ];
          }
        );
      };
    };
  };

  bootstrap = import <nixpkgs> { };

  nixpkgs = builtins.fromJSON (builtins.readFile ./nixpkgs.json);

  src = bootstrap.fetchFromGitHub {
    owner = "NixOS";
    repo  = "nixpkgs";
    inherit (nixpkgs) rev sha256;
  };

  pkgs = import src {
    config = {
      allowUnsupportedSystem = true;
      allowUnfree = true;
      allowBroken = false;
    };
    overlays = [ hasktorchOverlay synthesisOverlay ];
  };

  nullIfDarwin = arg: if pkgs.stdenv.hostPlatform.system == "x86_64-darwin" then null else arg;
  fixmkl = old: old // {
      shellHook = ''
        export LD_PRELOAD=${pkgs.mkl}/lib/libmkl_rt.so
      '';
    };
  doBenchmark = pkgs.haskell.lib.doBenchmark;
  dontBenchmark = pkgs.haskell.lib.dontBenchmark;

  base-compiler = pkgs.haskell.packages."${compiler}";
in
  rec {
    inherit nullIfDarwin;

    inherit (base-compiler)
      synthesis_cpu
      synthesis_cudatoolkit_9_2
      synthesis_cudatoolkit_10_1
    ;

    shell-synthesis_cpu              = (doBenchmark base-compiler.synthesis_cpu).env.overrideAttrs(fixmkl);
    shell-synthesis_cudatoolkit_9_2  = (doBenchmark base-compiler.synthesis_cudatoolkit_9_2).env.overrideAttrs(fixmkl);
    shell-synthesis_cudatoolkit_10_1 = (doBenchmark base-compiler.synthesis_cudatoolkit_10_1).env.overrideAttrs(fixmkl);
  }
