#!/usr/bin/env bash
# Compila ReGameDLL_CS (el "game dll": reglas de CS en C++).
#
# IMPORTANTE: el motor de este proyecto es de 64 bits, asi que el dll se compila
# con -DXASH_COMPAT=ON. Sin ese flag ReGameDLL intenta compilar a 32 bits (-m32)
# y en un sistema sin multilib falla con "bits/libc-header-start.h".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${PAPITA_SRC:-$ROOT/.src}"
GAME="$SRC/ReGameDLL_CS"
BUILD="$ROOT/.build/regamedll"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

log() { printf '\033[1;36m[gamedll]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[gamedll]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$GAME" ] || die "falta $GAME (ejecuta tools/fetch_sources.sh)"
command -v cmake >/dev/null || die "falta cmake (pip install cmake, o el paquete de tu distro)"

# CMAKE_POLICY_VERSION_MINIMUM: CMake >= 4 rechaza cmake_minimum_required(3.1).
cmake -S "$GAME" -B "$BUILD" \
	-DCMAKE_BUILD_TYPE=Release \
	-DXASH_COMPAT=ON \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$BUILD" -j"$JOBS"

DLL="$(find "$BUILD" -name 'cs*' -name '*.so' | head -1)"
[ -n "$DLL" ] || die "no se encontro el .so compilado"
log "game dll: ${DLL#"$ROOT"/}"
echo "$DLL"
