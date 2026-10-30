#!/usr/bin/env bash
# Empaqueta el proyecto en un zip listo para descargar y abrir en Godot.
# Uso: tools/package.sh [version]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-1.0.4}"
OUT_DIR="${OUT_DIR:-/home/user/releases}"
NAME="Papita-CS15-Reforged-v${VERSION}"
mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/$NAME.zip"
rm -f "$ZIP"

cd "$ROOT"
zip -rq "$ZIP" . \
    -x ".git/*" ".godot/*" "*.zip" "*.import" "__pycache__/*" ".venv-gdt/*" \
    -x "*.pyc" ".DS_Store" "export_presets.cfg"

echo "Generado: $ZIP"
echo "Contenido: $(zipinfo -1 "$ZIP" | wc -l) archivos, $(du -h "$ZIP" | cut -f1)"
