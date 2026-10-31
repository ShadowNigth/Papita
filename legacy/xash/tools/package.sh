#!/usr/bin/env bash
# Empaqueta SOLO el codigo (tools, config, docs, pins) en un zip.
#
# Por defecto NO incluye assets/: son material de Valve y no se pueden
# redistribuir (docs/AVISO_LEGAL.md). Con --with-assets se empaqueta todo,
# y ese zip es de uso privado: no lo publiques.
#
#   tools/package.sh v1.0.0
#   tools/package.sh v1.0.0 --with-assets
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-dev}"
shift || true
CON_ASSETS=0
[ "${1:-}" = "--with-assets" ] && CON_ASSETS=1

OUT_DIR="${OUT_DIR:-$ROOT/dist}"
NOMBRE="papita-cs15-${VERSION}"
mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/$NOMBRE.zip"
rm -f "$ZIP"

cd "$ROOT"
includes=(README.md NOTICE.md LICENSE .gitignore engine tools config docs run_server.sh run_client.sh)
[ "$CON_ASSETS" = "1" ] && includes+=(assets)

if command -v zip >/dev/null; then
	zip -rq "$ZIP" "${includes[@]}" \
		-x "*__pycache__*" "*.pyc" "*.log"
else
	# Sin zip: python se basta y sobra.
	python3 - "$ZIP" "${includes[@]}" <<'PY'
import sys, zipfile, pathlib
zip_path, *paths = sys.argv[1:]
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
    for p in paths:
        path = pathlib.Path(p)
        if path.is_file():
            z.write(path)
        for f in path.rglob("*"):
            if f.is_file() and "__pycache__" not in f.parts and f.suffix not in (".pyc", ".log"):
                z.write(f)
PY
fi

echo "Generado: $ZIP"
echo "Contenido: $(unzip -l "$ZIP" 2>/dev/null | tail -1 | awk '{print $2}') ficheros, $(du -h "$ZIP" | cut -f1)"
if [ "$CON_ASSETS" = "1" ]; then
	echo "AVISO: incluye assets de Valve. Uso privado, no redistribuir."
else
	echo "Solo codigo. Los assets se quedan en local."
fi
