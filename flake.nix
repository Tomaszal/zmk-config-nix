{
  description = "ZMK config Nix";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;
    rnix-lsp = {
      url = github:nix-community/rnix-lsp;
      inputs = {
        nixpkgs.follows = "nixpkgs";
        utils.follows = "flake-utils";
      };
    };
    mach-nix = {
      url = github:DavHau/mach-nix;
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rnix-lsp, mach-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        westManifest = builtins.fromJSON (builtins.readFile ./west-manifest.json);
        getWestModule = args@{ name, url, sha256, revision, clone-depth ? null, ... }: {
          path = args.path or name;
          root = !args ? path;
          src = pkgs.fetchgit { inherit url sha256; rev = revision; };
        };
        zephyr = getWestModule (builtins.head (builtins.filter ({ name, ... }: name == "zephyr") westManifest));
        pythonPkgs = mach-nix.lib."${system}".mkPython {
          requirements = builtins.readFile "${zephyr.src}/scripts/requirements-base.txt";
        };
        buildTools = with pkgs; [ cmake ccache ninja dtc dfu-util gcc-arm-embedded pythonPkgs ];
        exportToolchain = ''
          # Export Zephyr toolchain
          export ZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb
          export GNUARMEMB_TOOLCHAIN_PATH=${pkgs.gcc-arm-embedded}
        '';
      in
      with pkgs;
      {
        devShells.default = mkShell {
          nativeBuildInputs = [
            rnix-lsp.defaultPackage.${system}
            cocogitto
          ] ++ buildTools;
          shellHook = ''${exportToolchain}'';
        };

        packages.updateWestManifest = runCommand
          "update-west-manifest"
          { nativeBuildInputs = [ makeWrapper ]; }
          ''
            mkdir -p $out/bin $out/libexec
            cp ${./update-west-manifest.sh} $out/libexec/update-west-manifest.sh
            makeWrapper $out/libexec/update-west-manifest.sh $out/bin/update-west-manifest \
              --set PATH ${lib.makeBinPath [ pythonPkgs remarshal nix-prefetch-git jq git ]}
            patchShebangs $out
          '';

        packages.zmkBinary = { config, board, shield ? null }: stdenv.mkDerivation {
          name = "zmkBinary";
          nativeBuildInputs = [ git ] ++ buildTools;
          dontUseCmakeConfigure = true;
          dontUnpack = true;
          buildPhase =
            let
              westModules = map getWestModule westManifest;
              installWestModule = module:
                if module.root then
                  ''
                    # Generate a fake git repository for the module to be recognized by Zephir
                    mkdir -p ${module.path}
                    cp -r ${module.src}/. ${module.path}
                    cd ${module.path}
                    git init
                    git config user.email @
                    git config user.name @
                    git add .
                    git commit -m init
                    git update-ref refs/heads/manifest-rev HEAD
                    cd ../
                  ''
                else
                  ''
                    mkdir -p $(dirname ${module.path})
                    ln -s ${module.src} ${module.path}
                  '';
            in
            ''
              ${exportToolchain}

              # Export Zephyr Core (west zephyr-export)
              export CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH:$PWD/zephyr/share/zephyr-package/cmake
              export CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH:$PWD/zephyr/share/zephyrunittest-package/cmake

              # Export a home directory for build artifacts
              export HOME=$PWD/home
              mkdir home

              # Copy config files
              mkdir config
              cp ${./config/west.yml} config/west.yml
              cp -r ${config}/. config

              # Install West modules
              ${builtins.concatStringsSep "\n" (map installWestModule westModules)}

              # Build the ZMK binary
              west init -l config
              west build -s zmk/app -b ${board} -- -DZMK_CONFIG=$PWD/config ${ if shield != null then "-DSHIELD=${shield}" else "" }
            '';
          installPhase =
            ''
              mkdir -p $out/bin
              mv build/zephyr/zmk.uf2 $out/bin
            '';
        };
      }
    );
}
