#!/usr/bin/env bash
# Arranca el servidor dedicado.
#   ./run_server.sh                 -> de_dust2 en el puerto 27015
#   ./run_server.sh de_inferno      -> otro mapa
#   PORT=27016 ./run_server.sh      -> otro puerto
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP="${1:-de_dust2}"
PORT="${PORT:-27015}"
MAXPLAYERS="${MAXPLAYERS:-16}"

die() { printf '\033[1;31m[run]\033[0m %s\n' "$*" >&2; exit 1; }

[ -x "$ROOT/runtime/xash" ] || die "falta runtime/xash: ./tools/build_engine.sh dedicated"
[ -d "$ROOT/game/cstrike" ] || die "falta game/cstrike: python3 tools/assemble_gamedir.py"
[ -d "$ROOT/game/valve" ] || die "falta game/valve: python3 tools/bootstrap_valve.py o tools/make_free_base.py"
[ -f "$ROOT/game/cstrike/dlls/cs_amd64.so" ] || die "falta el game dll: ./tools/build_gamedll.sh"

echo "PAPITA · servidor dedicado"
echo "  mapa:   $MAP"
echo "  puerto: $PORT/udp"
echo "  consola: escribe 'quit' para salir"
echo

cd "$ROOT/game"
exec ../runtime/xash -dedicated -game cstrike \
	-port "$PORT" +maxplayers "$MAXPLAYERS" \
	+sv_lan 0 +map "$MAP"
