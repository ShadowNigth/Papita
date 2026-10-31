#!/usr/bin/env bash
# Compila Xash3D-FWGS (motor). Modos:
#   ./tools/build_engine.sh dedicated   -> servidor sin ventana (xash + filesystem_stdio.so)
#   ./tools/build_engine.sh client      -> cliente con ventana (necesita SDL2 + OpenGL)
#
# El motor usa waf, asi que no hace falta cmake. La primera vez tarda unos
# minutos; las siguientes reutilizan build/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${PAPITA_SRC:-$ROOT/.src}"
ENGINE="$SRC/xash3d-fwgs"
MODE="${1:-dedicated}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
OUT="$ROOT/runtime"

log()  { printf '\033[1;36m[engine]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[engine]\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$ENGINE/wscript" ] || die "falta $ENGINE (ejecuta tools/fetch_sources.sh)"

# Los headers generados (build.h) no estan versionados: se crean aqui.
python3 "$ROOT/tools/gen_build_h.py" "$ENGINE"

cd "$ENGINE"
case "$MODE" in
	dedicated)
		# -8 = permitir 64 bits; --dedicated = sin video ni sonido.
		./waf configure -8 --dedicated --disable-werror
		./waf build -j"$JOBS"
		mkdir -p "$OUT"
		cp build/engine/xash "$OUT/"
		cp build/filesystem/filesystem_stdio.so "$OUT/"
		# Recursos libres que el motor espera junto al ejecutable.
		EXTRAS="$ENGINE/3rdparty/extras/xash-extras"
		[ -d "$EXTRAS" ] && cp -n "$EXTRAS"/cacert.pem "$EXTRAS"/*.fnt "$EXTRAS"/gamecontrollerdb.txt "$OUT/" 2>/dev/null || true
		log "servidor en $OUT/xash"
		;;
	client)
		command -v pkg-config >/dev/null || die "faltan pkg-config y las cabeceras de SDL2"
		pkg-config --exists sdl2 || die "falta libsdl2-dev (o equivalente)"
		./waf configure -8 --disable-werror --enable-all-renderers
		./waf build -j"$JOBS"
		mkdir -p "$OUT"
		cp build/engine/xash "$OUT/"
		cp build/filesystem/filesystem_stdio.so "$OUT/"
		for ref in build/ref/*/*.so; do [ -f "$ref" ] && cp "$ref" "$OUT/"; done
		log "cliente en $OUT/xash (ejecuta ./run_client.sh)"
		;;
	*)
		die "modo desconocido: $MODE (usa dedicated o client)"
		;;
esac
