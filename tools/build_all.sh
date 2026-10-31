#!/usr/bin/env bash
# Pipeline completo: fuentes -> motor -> game dll -> gamedir -> prueba.
#
#   ./tools/build_all.sh            # servidor dedicado + gamedir + smoke test
#   ./tools/build_all.sh --client   # ademas el cliente (requiere SDL2/OpenGL)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENTE=0
[ "${1:-}" = "--client" ] && CLIENTE=1

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

log "1/5 fuentes fijadas"
"$ROOT/tools/fetch_sources.sh"

log "2/5 motor (servidor dedicado)"
"$ROOT/tools/build_engine.sh" dedicated

log "3/5 game dll"
DLL="$("$ROOT/tools/build_gamedll.sh" | tail -1)"

log "4/5 gamedir"
python3 "$ROOT/tools/assemble_gamedir.py" \
	--dll "$DLL" \
	--regamedll "$ROOT/.src/ReGameDLL_CS"

if [ "$CLIENTE" = "1" ]; then
	log "4b/5 cliente"
	"$ROOT/tools/build_client.sh"
fi

if [ ! -d "$ROOT/game/valve" ]; then
	log "5/5 base libre de pruebas (valve/)"
	python3 "$ROOT/tools/make_free_base.py"
else
	log "5/5 base valve/ ya presente"
fi

log "smoke test"
"$ROOT/tools/smoke_test.sh"
