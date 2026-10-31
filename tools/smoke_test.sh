#!/usr/bin/env bash
# Arranca el servidor dedicado unos segundos por mapa y comprueba que el .bsp,
# el game dll y las entidades cargan de verdad. Sale con codigo != 0 si algun
# mapa no llega a "player server started".
#
#   ./tools/smoke_test.sh                 # todos los mapas
#   ./tools/smoke_test.sh de_dust2        # uno solo
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEGUNDOS="${SEGUNDOS:-12}"
BIN="$ROOT/runtime/xash"
GAME="$ROOT/game"
LOGS="$ROOT/.build/logs"

ok=0; fallos=0
if [ ! -x "$BIN" ]; then
	echo "error: falta $BIN (tools/build_engine.sh dedicated)" >&2
	exit 1
fi
if [ ! -d "$GAME/cstrike" ]; then
	echo "error: falta $GAME/cstrike (tools/assemble_gamedir.py)" >&2
	exit 1
fi

mkdir -p "$LOGS"
mapas=("$@")
if [ ${#mapas[@]} -eq 0 ]; then
	mapas=()
	while IFS= read -r m; do mapas+=("$m"); done < <(
		find "$GAME/cstrike/maps" -name '*.bsp' -printf '%f\n' | sed 's/\.bsp$//' | sort
	)
fi

for mapa in "${mapas[@]}"; do
	log="$LOGS/$mapa.log"
	(cd "$GAME" && timeout "$SEGUNDOS" "$BIN" -dedicated -game cstrike \
		+sv_lan 1 +maxplayers 12 +map "$mapa" >"$log" 2>&1) || true

	if grep -q "player server started" "$log"; then
		n_err=$(grep -c "Could not load" "$log" || true)
		printf '\033[1;32m  OK  \033[0m %-14s %s recursos ausentes\n' "$mapa" "$n_err"
		ok=$((ok + 1))
	else
		printf '\033[1;31m FALLO\033[0m %-14s ver %s\n' "$mapa" "${log#"$ROOT"/}"
		fallos=$((fallos + 1))
	fi
done

# Resumen de lo que pide el juego y no existe: sirve para saber que falta.
if [ -d "$LOGS" ]; then
	grep -rhoE "Could not load model (models|sprites)/[a-zA-Z0-9_/.-]+" "$LOGS" 2>/dev/null \
		| awk '{print $5}' | sort -u > "$LOGS/faltantes.txt" || true
	if [ -s "$LOGS/faltantes.txt" ]; then
		echo
		echo "Recursos que el juego pide y no estan (los primeros 10):"
		head -10 "$LOGS/faltantes.txt" | sed 's/^/  - /'
		echo "  (lista completa en ${LOGS#"$ROOT"/}/faltantes.txt)"
	fi
fi

echo
echo "$ok mapas OK, $fallos con fallo"
[ "$fallos" -eq 0 ]
