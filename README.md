# X11SpotSearch

A Spotlight-like application launcher for X11 environments. It combines a fuzzy finder for desktop entries with direct X11 integration via XCB, and uses Cairo and Pango for text rendering.

## Features

- **Written in Zig**: Compiled natively for a minimal resource footprint.
- **Fuzzy Search**: Find and launch applications using fuzzy matching across your system's desktop entries.
- **X11 Native**: Interfaces directly with XCB rather than relying on large GUI toolkits like GTK or Qt.
- **Daemon Mode**: Run a background process (`--deamon` or `-d`) that listens for a global hotkey (default: `Super + Space`) to spawn the launcher.
- **Oneshot Mode**: Run the launcher directly to search and launch an application, exiting immediately after.
- **Text Rendering**: Utilizes Cairo and Pango for text rendering.
- **AppImage Support**: Includes a build script (`package-appimage.sh`) to bundle the application and its shared library dependencies into a portable AppImage.

## Prerequisites

To build from source, you need **Zig** (version >= 0.15) and the following C development libraries installed:

- `libxcb-dev` / `xcb`
- `libxcb-icccm4-dev` / `xcb-icccm`
- `libxcb-ewmh-dev` / `xcb-ewmh`
- `libxcb-xkb-dev` / `xcb-xkb`
- `libxkbcommon-dev` / `xkbcommon`
- `libxkbcommon-x11-dev` / `xkbcommon-x11`
- `libcairo2-dev` / `cairo`
- `libpango1.0-dev` / `pangocairo`

*(Note: Package names are based on Debian/Ubuntu and may vary on distributions like Arch or Fedora.)*

## Building

To build the project natively using the Zig build system:

```bash
zig build -Doptimize=ReleaseFast
```

The resulting binary will be placed in `zig-out/bin/X11SpotSearch`.

### Packaging as an AppImage

To build the executable and package it into a self-contained AppImage:

```bash
./package-appimage.sh
```

This script will compile the application, download `appimagetool` if necessary, bundle the required dynamic libraries, and produce an `X11SpotSearch-x86_64.AppImage` in the project root.

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

## Configuration

Currently, configuration (like the default hotkey) is compiled into the binary. 
The default trigger in daemon mode is set to the **Mod4 (Super)** key + **Space** key. If you wish to change this, you can edit the `src/mode.zig` file before compiling:

```zig
config.hotkey_mod = 0x40; // Mod4Mask (Super key)
config.hotkey_keysym = c.XKB_KEY_space;
```
