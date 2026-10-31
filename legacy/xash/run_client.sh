#!/usr/bin/env bash
# Arranca el cliente con ventana (necesita haber compilado engine client + cs16-client).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP="${1:-}"

die() { printf '\033[1;31m[run]\033[0m %s\n' "$*" >&2; exit 1; }

[ -x "$ROOT/runtime/xash" ] || die "falta runtime/xash"
[ -d "$ROOT/game/cstrike" ] || die "falta game/cstrike"
[ -d "$ROOT/game/valve" ] || die "falta game/valve (recursos base de Half-Life)"

# El motor busca las librerias del cliente en <gamedir>/cl_dll/.
CLDLL="$ROOT/game/cstrike/cl_dll"
mkdir -p "$CLDLL"
shopt -s nullglob
enlazado=0
for lib in "$ROOT"/runtime/client*.so "$ROOT"/runtime/menu*.so; do
	ln -sf "$lib" "$CLDLL/$(basename "$lib")"
	enlazado=1
done
[ "$enlazado" = "1" ] || die "no hay client_*.so en runtime/: ./tools/build_client.sh"

cd "$ROOT/game"
if [ -n "$MAP" ]; then
	exec ../runtime/xash -game cstrike +map "$MAP"
else
	exec ../runtime/xash -game cstrike
fi
