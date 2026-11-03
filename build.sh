#!/bin/bash
# Compila Muesca.app. Requiere las Command Line Tools de Xcode:  xcode-select --install
#   ./build.sh             → compila en ./build/Muesca.app
#   ./build.sh --install   → además la instala en /Applications y la abre
set -euo pipefail
cd "$(dirname "$0")"

# Se compila y firma fuera de la carpeta del proyecto: si está en una carpeta
# sincronizada con iCloud (Escritorio, Documentos…), macOS añade atributos que
# impiden firmar la app.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/muesca-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/Muesca.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ Compilando…"
swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit -framework SwiftUI -framework IOKit -framework CoreImage -framework EventKit -framework CoreLocation -framework CoreAudio -framework AVKit -framework IOBluetooth -framework ApplicationServices -framework CoreMediaIO \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Muesca"

cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Fecha de la última revisión = fecha de compilación
/usr/libexec/PlistBuddy -c "Add :MuescaRevisionDate string $(date +%Y-%m-%d)" "$APP/Contents/Info.plist"
xattr -cr "$APP"

# Firma con un certificado estable para que macOS recuerde los permisos
# (calendario, ubicación, Spotify, Accesibilidad) entre compilaciones.
IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk '/"Muesca Code Signing"/ {print $2; exit}')
if [[ -n "$IDENTITY" ]]; then
  echo "→ Firmando con «Muesca Code Signing»…"
  codesign --force --deep --sign "$IDENTITY" "$APP"
else
  echo "→ Firmando (ad-hoc; macOS pedirá permisos tras cada compilación)…"
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "→ Firma verificada"

# Copia del resultado en ./build (referencia)
rm -rf build && mkdir -p build
ditto "$APP" build/Muesca.app

if [[ "${1:-}" == "--install" ]]; then
  echo "→ Instalando en /Applications…"
  pkill -x Muesca 2>/dev/null || true
  rm -rf /Applications/Muesca.app
  ditto "$APP" /Applications/Muesca.app
  open /Applications/Muesca.app
  echo "✓ Instalada y abierta: /Applications/Muesca.app"
  exit 0
fi

echo "✓ Listo: build/Muesca.app"
echo "  Instálala con:  ./build.sh --install"
