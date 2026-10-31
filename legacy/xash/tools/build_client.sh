#!/usr/bin/env bash
# Compila cs16-client (el "client dll": HUD, menus, prediccion, viewmodels).
# Produce cl_dll/client_amd64.so y menu_amd64.so.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${PAPITA_SRC:-$ROOT/.src}"
CLIENT="$SRC/cs16-client"
BUILD="$ROOT/.build/cs16-client"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

log() { printf '\033[1;36m[client]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[client]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$CLIENT" ] || die "falta $CLIENT (ejecuta tools/fetch_sources.sh)"
command -v cmake >/dev/null || die "falta cmake"

cmake -S "$CLIENT" -B "$BUILD" \
	-DCMAKE_BUILD_TYPE=Release \
	-DXASH_64BIT=ON \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$BUILD" -j"$JOBS"

mkdir -p "$ROOT/runtime"
find "$BUILD" -name '*.so' -exec cp {} "$ROOT/runtime/" \;
log "librerias copiadas a runtime/"
