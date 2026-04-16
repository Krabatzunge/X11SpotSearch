{
  description = "A Spotlight-like application launcher for X11 environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # zig-overlay provides Zig nightly/master builds not yet in nixpkgs stable.
    # The project requires minimum_zig_version = "0.15.2" (pre-release).
    zig-overlay.url = "github:mitchellh/zig-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Use Zig 0.15.2 from zig-overlay to match minimum_zig_version = "0.15.2"
        zig = zig-overlay.packages.${system}."0.15.2";

        # C libraries required by build.zig / c.zig
        # - xorg.xcbutilwm  → libxcb-wm (provides xcb-icccm + xcb-ewmh headers/libs)
        # - xorg.libxcb     → xcb, xcb-xkb
        # - libxkbcommon    → xkbcommon, xkbcommon-x11
        # - wayland         → wayland-client
        # - wayland-protocols / wlr-protocols → protocol XMLs
        # - cairo           → cairo, cairo-xcb
        # - pango           → pangocairo
        # - librsvg         → librsvg-2.0
        # - curl            → curl
        buildInputs = with pkgs; [
          xorg.libxcb
          xorg.xcbutilwm
          libxkbcommon
          wayland
          wayland-protocols
          wlr-protocols
          cairo
          pango
          librsvg
          curl
        ];

        nativeBuildInputs = with pkgs; [
          zig
          pkg-config
          wayland-scanner
        ];
      in
      {
        packages = {
          default = self.packages.${system}.X11SpotSearch;

          X11SpotSearch = pkgs.stdenv.mkDerivation {
            pname = "X11SpotSearch";
            version = "0.0.0";
            src = ./.;

            inherit nativeBuildInputs buildInputs;

            # Let Zig find system libraries via pkg-config
            ZIG_SYSTEM_LINKER_HACK = "1";

            preBuild = ''
              # Generate Wayland protocol glue code (these files are not checked into git)
              mkdir -p src/wayland/generated

              WLR_XML="${pkgs.wlr-protocols}/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml"
              XDG_XML="${pkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"

              wayland-scanner client-header "$WLR_XML" src/wayland/generated/wlr-layer-shell-unstable-v1-client-protocol.h
              wayland-scanner private-code  "$WLR_XML" src/wayland/generated/wlr-layer-shell-unstable-v1-client-protocol.c
              wayland-scanner client-header "$XDG_XML" src/wayland/generated/xdg-shell-client-protocol.h
              wayland-scanner private-code  "$XDG_XML" src/wayland/generated/xdg-shell-client-protocol.c
            '';

            buildPhase = ''
              runHook preBuild
              export HOME=$TMPDIR
              zig build -Doptimize=ReleaseFast \
                --prefix $out \
                --global-cache-dir "$TMPDIR/.zig-cache"
            '';

            # zig build --prefix already installs to $out
            dontInstall = true;

            # Install the .desktop file
            postInstall = ''
              install -Dm644 X11SpotSearch.desktop \
                "$out/share/applications/X11SpotSearch.desktop"
            '';

            meta = with pkgs.lib; {
              description = "A Spotlight-like application launcher for X11 environments";
              longDescription = ''
                X11SpotSearch is a Spotlight-style application launcher for X11.
                It provides fuzzy search over desktop entries, direct X11 integration
                via XCB, icon support (PNG/SVG/XPM), daemon mode with a configurable
                global hotkey, and text rendering via Cairo and Pango.
              '';
              homepage = "https://github.com/Krabatzunge/X11SpotSearch";
              license = licenses.gpl3Only;
              maintainers = [ ];
              platforms = [ "x86_64-linux" "aarch64-linux" ];
              mainProgram = "X11SpotSearch";
            };
          };
        };

        # Development shell with all build and runtime dependencies
        devShells.default = pkgs.mkShell {
          name = "x11spotsearch-dev";

          nativeBuildInputs = nativeBuildInputs;
          buildInputs = buildInputs;

          # Useful dev tools
          packages = with pkgs; [
            gdb
            valgrind
          ];

          shellHook = ''
            echo "X11SpotSearch dev shell (Zig $(zig version))"
            echo "Build:  zig build"
            echo "Run:    zig build run"
            echo "Test:   zig build test"
          '';
        };
      }
    );
}
