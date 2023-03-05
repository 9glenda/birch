{
  description = "An over-engineered birch script ";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixos-22.11";

  outputs = { self, nixpkgs }:
    let

      # to work with older version of flakes
      lastModifiedDate = self.lastModifiedDate or self.lastModified or "19700101";

      # Generate a user-friendly version number.
      version = builtins.substring 0 8 lastModifiedDate;

      # System types to support.
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlay ]; });

    in

    {

      # A Nixpkgs overlay.
      overlay = final: prev: {

        birch = with final; stdenv.mkDerivation rec {
          name = "birch-${version}";
          src = ./.;

          #unpackPhase = ":";

          buildPhase = '':'';

          installPhase =
            ''
              mkdir -p $out/bin $out/share
              install birch $out/bin/ 
            '';
        };

      };

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        {
          inherit (nixpkgsFor.${system}) birch;
        });

      # The default package for 'nix build'. This makes sense if the
      # flake provides only one package or there is a clear "main"
      # package.
      defaultPackage = forAllSystems (system: self.packages.${system}.birch);

      # A NixOS module, if applicable (e.g. if the package provides a system service).
      nixosModules.birch =
        { pkgs, ... }:
        {
          nixpkgs.overlays = [ self.overlay ];

          environment.systemPackages = [ pkgs.birch ];

          #systemd.services = { ... };
        };

      # Tests run by 'nix flake check' and by Hydra.
      checks = forAllSystems
        (system:
          with nixpkgsFor.${system};

          {
            inherit (self.packages.${system}) birch;

            # Additional tests, if applicable.
            test = stdenv.mkDerivation {
              name = "birch-test-${version}";

              buildInputs = [ birch shellcheck ];

              unpackPhase = "true";

              buildPhase = ''
                echo 'running some integration tests'
                [[ $(shellcheck ${birch}/bin/birch) ]]
              '';

              installPhase = "mkdir -p $out";
            };
          }

          // lib.optionalAttrs stdenv.isLinux {
            # A VM test of the NixOS module.
            vmTest =
              with import (nixpkgs + "/nixos/lib/testing-python.nix")
                {
                  inherit system;
                };

              makeTest {
                name = "vmTest";
                nodes = {
                  client = { ... }: {
                    imports = [ self.nixosModules.birch ];
                  };
                };

                testScript =
                  ''
                    start_all()
                    client.wait_for_unit("multi-user.target")
                    #client.succeed("birch")
                  '';
              };
          }
        );

    };
}
