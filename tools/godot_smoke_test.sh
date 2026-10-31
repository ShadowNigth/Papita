#!/usr/bin/env bash
# Prueba de integración en modo headless. Carga el proyecto, procesa su escena
# principal y construye los ocho modelos de actor para cubrir mdl_reader.gd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
GODOT_TIMEOUT="${GODOT_TIMEOUT:-180s}"
LOG_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/papita-godot-smoke"
mkdir -p "$LOG_DIR"

emitir_error_github() {
    local nombre="$1"
    local log="$2"
    local detalle="$(tail -n 25 "$log" | tr '\r\n' '  ' | cut -c1-2500)"
    detalle="${detalle//'%'/'%25'}"
    detalle="${detalle//$'\r'/'%0D'}"
    detalle="${detalle//$'\n'/'%0A'}"
    printf '::error title=Godot smoke: %s::%s\n' "$nombre" "$detalle"
}

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
        emitir_error_github "$nombre" "$log"
        return "$estado"
    fi
    if grep -Eiq '(^|[[:space:]])(SCRIPT ERROR|Parse Error|ERROR):' "$log"; then
        echo "Godot informó errores durante '$nombre'." >&2
        emitir_error_github "$nombre" "$log"
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
    emitir_error_github "arranque (faltan actores)" "$LOG_DIR/arranque.log"
    exit 1
fi

# Verifica con el motor los ejes y la escala visual de los ocho modelos: tras
# convertir GoldSrc a Godot, deben medir entre 1,5 y 1,95 m de alto.
run_godot escala_modelos --script res://tools/godot_actor_validate.gd

echo "Prueba headless de Godot completada sin errores."
