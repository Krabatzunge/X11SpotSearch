#!/bin/bash
set -euo pipefail

APP_NAME="X11SpotSearch"
ARCH="$(uname -m)"
APPDIR="${APP_NAME}.AppDir"
APPIMAGETOOL="appimagetool-${ARCH}.AppImage"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage"

echo "=== Building ${APP_NAME} ==="
zig build -Doptimize=ReleaseFast

echo "=== Creating AppDir structure ==="
rm -rf "${APPDIR}"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/lib"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

# Copy the binary
cp "zig-out/bin/${APP_NAME}" "${APPDIR}/usr/bin/"

# Copy the .desktop file
cp "${APP_NAME}.desktop" "${APPDIR}/"

# Generate a simple placeholder icon (1x1 red PNG) if no icon exists.
ICON_PATH="${APPDIR}/${APP_NAME}.png"
if command -v convert &>/dev/null; then
  convert -size 256x256 xc:'#89b4fa' -gravity center \
    -pointsize 120 -fill white -annotate 0 "S" \
    PNG:"${ICON_PATH}" 2>/dev/null ||
    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' >"${ICON_PATH}"
else
  # Minimal valid 1x1 PNG as fallback
  printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' >"${ICON_PATH}"
fi
# Also place icon in hicolor for desktop integration
cp "${ICON_PATH}" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/"

echo "=== Bundling shared library dependencies ==="

# Collect all shared library dependencies (excluding core system libs
# that should always be present on the host: libc, libm, libdl, ld-linux,
# libpthread, librt, libstdc++).
EXCLUDE_PATTERN="linux-vdso|ld-linux|libc\.so|libm\.so|libdl\.so|libpthread|librt\.so|libstdc\+\+"

ldd "zig-out/bin/${APP_NAME}" |
  grep -v "(${EXCLUDE_PATTERN})" |
  awk '/=>/ { print $3 }' |
  sort -u |
  while read -r lib; do
    if [ -f "$lib" ]; then
      echo "  Bundling: $(basename "$lib")"
      cp -L "$lib" "${APPDIR}/usr/lib/"
    fi
  done

# Some libraries load plugins/modules at runtime. Bundle common ones.
# Pango modules (needed for text rendering):
PANGO_LIB_DIR=""
for dir in /usr/lib/${ARCH}-linux-gnu/pango /usr/lib/pango /usr/lib64/pango; do
  if [ -d "$dir" ]; then
    PANGO_LIB_DIR="$dir"
    break
  fi
done
if [ -n "${PANGO_LIB_DIR}" ]; then
  echo "  Bundling Pango modules from ${PANGO_LIB_DIR}"
  cp -rL "${PANGO_LIB_DIR}" "${APPDIR}/usr/lib/" 2>/dev/null || true
fi

# GDK-Pixbuf loaders (if needed):
GDK_PIXBUF_DIR=""
for dir in /usr/lib/${ARCH}-linux-gnu/gdk-pixbuf-2.0 /usr/lib/gdk-pixbuf-2.0 /usr/lib64/gdk-pixbuf-2.0; do
  if [ -d "$dir" ]; then
    GDK_PIXBUF_DIR="$dir"
    break
  fi
done
if [ -n "${GDK_PIXBUF_DIR}" ]; then
  echo "  Bundling GDK-Pixbuf loaders from ${GDK_PIXBUF_DIR}"
  cp -rL "${GDK_PIXBUF_DIR}" "${APPDIR}/usr/lib/" 2>/dev/null || true
fi

echo "=== Creating AppRun ==="

# AppRun script: sets up the environment so bundled libraries and
# resources are found before system ones.
cat >"${APPDIR}/AppRun" <<'APPRUN_EOF'
#!/bin/bash
SELF_DIR="$(dirname "$(readlink -f "$0")")"

export LD_LIBRARY_PATH="${SELF_DIR}/usr/lib:${LD_LIBRARY_PATH:-}"

# Pango needs to find its modules
if [ -d "${SELF_DIR}/usr/lib/pango" ]; then
    export PANGO_LIBDIR="${SELF_DIR}/usr/lib"
fi

# GDK-Pixbuf loader cache
if [ -d "${SELF_DIR}/usr/lib/gdk-pixbuf-2.0" ]; then
    export GDK_PIXBUF_MODULE_FILE="${SELF_DIR}/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
    export GDK_PIXBUF_MODULEDIR="${SELF_DIR}/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders"
fi

exec "${SELF_DIR}/usr/bin/X11SpotSearch" "$@"
APPRUN_EOF
chmod +x "${APPDIR}/AppRun"

echo "=== Downloading appimagetool (if needed) ==="

if [ ! -f "${APPIMAGETOOL}" ]; then
  echo "  Downloading from ${APPIMAGETOOL_URL}"
  curl -L -o "${APPIMAGETOOL}" "${APPIMAGETOOL_URL}"
  chmod +x "${APPIMAGETOOL}"
fi

echo "=== Building AppImage ==="

# ARCH must be set for appimagetool
export ARCH
./"${APPIMAGETOOL}" "${APPDIR}" "${APP_NAME}-${ARCH}.AppImage"

echo ""
echo "=== Done! ==="
echo "AppImage created: ${APP_NAME}-${ARCH}.AppImage"
echo ""
echo "To run it:"
echo "  chmod +x ${APP_NAME}-${ARCH}.AppImage"
echo "  ./${APP_NAME}-${ARCH}.AppImage"
