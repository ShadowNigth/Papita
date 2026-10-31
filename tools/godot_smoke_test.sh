#!/usr/bin/env bash
# Prueba de integración en modo headless. Carga el proyecto, procesa su escena
# principal y construye los ocho modelos de actor para cubrir mdl_reader.gd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
GODOT_TIMEOUT="${GODOT_TIMEOUT:-180s}"
LOG_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/papita-godot-smoke"
mkdir -p "$LOG_DIR"

run_godot() {
    local nombre="$1"
    shift
    local log="$LOG_DIR/$nombre.log"
    local estado=0

    echo "== Godot: $nombre =="
    if command -v timeout >/dev/null 2>&1; then
        timeout "$GODOT_TIMEOUT" "$GODOT_BIN" --headless --path "$ROOT" "$@" >"$log" 2>&1 || estado=$?
    else
        "$GODOT_BIN" --headless --path "$ROOT" "$@" >"$log" 2>&1 || estado=$?
    fi
    cat "$log"
    if (( estado != 0 )); then
        echo "Godot terminó con código $estado durante '$nombre'." >&2
        return "$estado"
    fi
    if grep -Eiq '(^|[[:space:]])(SCRIPT ERROR|Parse Error|ERROR):' "$log"; then
        echo "Godot informó errores durante '$nombre'." >&2
        return 1
    fi
}

"$GODOT_BIN" --version

# El editor importa el proyecto y comprueba los recursos y scripts registrados.
run_godot editor --editor --quit

# _ready() carga de_dust2 y crea las ocho facciones; esto ejercita el lector
# real de MDL, la expansión de strips/fans, la asignación de UV y el skinning.
run_godot arranque --quit-after 2 -- --map de_dust2 --bots 8
if ! grep -Fq '[papita] 8 actores animados' "$LOG_DIR/arranque.log"; then
    echo "La escena no confirmó la carga de los ocho modelos de actor." >&2
    exit 1
fi

echo "Prueba headless de Godot completada sin errores."
