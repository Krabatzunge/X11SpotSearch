# X11SpotSearch

A Spotlight-like application launcher for X11 environments. It combines a fuzzy finder for desktop entries with direct X11 integration via XCB, and uses Cairo and Pango for text rendering.

## Features

- **Written in Zig**: Compiled natively for a minimal resource footprint.
- **Fuzzy Search**: Find and launch applications using fuzzy matching across your system's desktop entries.
- **Category Search**: Prefix your query with a `#tag` to restrict matching to a specific field (name, description, or category).
- **Icon Support**: Application icons (PNG, SVG, XPM) are automatically loaded from your system themes and rendered alongside search results.
- **X11 Native**: Interfaces directly with XCB rather than relying on large GUI toolkits like GTK or Qt.
- **Daemon Mode**: Run a background process (`--deamon` or `-d`) that listens for a global hotkey (default: `Super + Space`) to spawn the launcher.
- **Oneshot Mode**: Run the launcher directly to search and launch an application, exiting immediately after.
- **Text Rendering**: Utilizes Cairo and Pango for text rendering.
- **AppImage Support**: Includes a build script (`package-appimage.sh`) to bundle the application and its shared library dependencies into a portable AppImage.

## Platform Support

X11SpotSearch supports both **X11** and **Wayland** display servers. The backend is selected automatically at runtime.

## Installation & Building

### NixOS (recommended for Nix users)

The project includes a Nix flake. No manual dependency management needed.

**Run directly (without installing):**
```bash
nix run github:Krabatzunge/X11SpotSearch/wayland
```

**Install to your profile:**
```bash
nix profile install github:Krabatzunge/X11SpotSearch/wayland
```

**Build locally:**
```bash
nix build .#X11SpotSearch
./result/bin/X11SpotSearch
```

> The Nix flake handles all dependencies and generates required Wayland protocol files automatically.

### Other Linux Distros (Ubuntu, Fedora, Arch, etc.)

#### Prerequisites

You need **Zig** (version >= 0.15.2) and the following C development libraries:

- `libxcb-dev` / `xcb`
- `libxcb-icccm4-dev` / `xcb-icccm`
- `libxcb-ewmh-dev` / `xcb-ewmh`
- `libxcb-xkb-dev` / `xcb-xkb`
- `libxkbcommon-dev` / `xkbcommon`
- `libxkbcommon-x11-dev` / `xkbcommon-x11`
- `libcairo2-dev` / `cairo`
- `libpango1.0-dev` / `pangocairo`
- `librsvg2-dev` / `librsvg`
- `libwayland-dev` / `wayland` (for Wayland support)
- `wayland-protocols` (for Wayland support)

*(Package names are Debian/Ubuntu-based and may vary on other distributions.)*

For Wayland support, you also need to generate the protocol files:
```bash
mkdir -p src/wayland/generated
wayland-scanner client-header /usr/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml src/wayland/generated/wlr-layer-shell-unstable-v1-client-protocol.h
wayland-scanner private-code  /usr/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml src/wayland/generated/wlr-layer-shell-unstable-v1-client-protocol.c
wayland-scanner client-header /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml src/wayland/generated/xdg-shell-client-protocol.h
wayland-scanner private-code  /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml src/wayland/generated/xdg-shell-client-protocol.c
```

#### Build from source

```bash
zig build -Doptimize=ReleaseFast
```

The binary will be placed in `zig-out/bin/X11SpotSearch`.

#### Packaging as an AppImage

To bundle the application into a portable, self-contained AppImage:

```bash
./package-appimage.sh
```

This compiles the application, downloads `appimagetool` if necessary, bundles required shared libraries, and produces `X11SpotSearch-x86_64.AppImage` in the project root.

> **Note:** AppImages built on NixOS are automatically patched for portability and will work on standard Linux distributions. The AppImage is the recommended way to distribute to non-NixOS users.

## Usage

### Standalone (Oneshot)

You can run the launcher directly to open the prompt once:

```bash
./zig-out/bin/X11SpotSearch
```

### Daemon Mode

To run X11SpotSearch in the background and listen for a hotkey (default is **Super + Space**), run the binary with the `-d` (or `--deamon`) flag:

```bash
./zig-out/bin/X11SpotSearch -d
```

When running in daemon mode, pressing `Super + Space` will spawn a new instance of the launcher.

## Search Tags

Queries can be prefixed with a `#tag` to restrict fuzzy matching to a specific field of each `.desktop` entry. When a tag is active, a small pill/chip is rendered inside the search bar to indicate the active mode.

| Prefix | Field searched |
|--------|----------------|
| *(none)* | Name and description |
| `#name` | Application name only |
| `#desc` | Description / comment only |
| `#cat` | Category field only |

**Examples:**

```
firefox          # search name + description
#name fire       # match only against app names
#desc browser    # match only against descriptions
#cat office      # match only against categories
```

## Configuration

Currently, configuration (like the default hotkey) is compiled into the binary. 
The default trigger in daemon mode is set to the **Mod4 (Super)** key + **Space** key. If you wish to change this, you can edit the `src/mode.zig` file before compiling:

```zig
config.hotkey_mod = 0x40; // Mod4Mask (Super key)
config.hotkey_keysym = c.XKB_KEY_space;
```
