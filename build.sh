#!/bin/bash
# Compila Muesca.app. Requiere las Command Line Tools de Xcode:  xcode-select --install
#   ./build.sh             → compila en ./build/Muesca.app
#   ./build.sh --install   → además la instala en /Applications y la abre
#   ./build.sh --universal → app universal (chip Apple + Intel) y Muesca-<versión>.zip para publicar
set -euo pipefail
cd "$(dirname "$0")"

# Se compila y firma fuera de la carpeta del proyecto: si está en una carpeta
# sincronizada con iCloud (Escritorio, Documentos…), macOS añade atributos que
# impiden firmar la app.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/muesca-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/Muesca.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

INSTALL=0; UNIVERSAL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --universal) UNIVERSAL=1 ;;
  esac
done

FRAMEWORKS=(-framework AppKit -framework SwiftUI -framework IOKit -framework CoreImage -framework EventKit
            -framework CoreLocation -framework CoreAudio -framework AVKit -framework IOBluetooth
            -framework ApplicationServices -framework CoreMediaIO)

compile() {   # $1 = arquitectura (arm64 | x86_64), $2 = salida
  swiftc -O -parse-as-library -target "$1-apple-macos13.0" "${FRAMEWORKS[@]}" Sources/*.swift -o "$2"
}

if [[ $UNIVERSAL == 1 ]]; then
  echo "→ Compilando para chip Apple (arm64)…"
  compile arm64 "$WORK/Muesca-arm64"
  echo "→ Compilando para Intel (x86_64)…"
  compile x86_64 "$WORK/Muesca-x86_64"
  lipo -create -output "$APP/Contents/MacOS/Muesca" "$WORK/Muesca-arm64" "$WORK/Muesca-x86_64"
  echo "→ App universal: $(lipo -archs "$APP/Contents/MacOS/Muesca")"
else
  echo "→ Compilando…"
  compile "$(uname -m)" "$APP/Contents/MacOS/Muesca"
fi

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

if [[ $UNIVERSAL == 1 ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
  ZIP="Muesca-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "→ Paquete para publicar: $ZIP"
fi

if [[ $INSTALL == 1 ]]; then
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
