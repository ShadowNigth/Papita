#!/usr/bin/env python3
"""Validador estatico de GDScript sin necesidad de tener Godot instalado.

Comprueba tres cosas sobre `scripts/`:

1. **Sintaxis**: parsea cada `.gd` con `gdtoolkit` (el mismo parser que usa
   gdformat/gdlint, escrito a partir de la gramatica oficial).
2. **API de Godot 4.4**: contrasta cada `Clase.metodo(...)` y `Clase.CONSTANTE`
   contra `docs/godot44_api.json.gz` (volcado de la API del motor).
3. **Rutas**: verifica que cada `preload("res://...")` apunte a un fichero real.

No sustituye a abrir el proyecto en Godot, pero atrapa lo que rompe un proyecto
el primer dia: erratas en nombres de metodos, clases que no existen y rutas mal
escritas.

    pip install gdtoolkit
    python3 tools/gdscript_check.py
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API_JSON = ROOT / "docs" / "godot44_api.json.gz"

RE_CLASE_METODO = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\.([a-z_][a-z0-9_]*)\s*\(")
RE_CLASE_CONST = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\.([A-Z][A-Z0-9_]{2,})\b")
RE_PRELOAD = re.compile(r'preload\(\s*"(res://[^"]+)"\s*\)')
RE_EXTENDS = re.compile(r"^extends\s+([A-Za-z0-9_]+)", re.MULTILINE)
RE_CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.MULTILINE)
RE_FUNC = re.compile(r"^func\s+(\w+)\s*\(", re.MULTILINE)
RE_SIGNAL = re.compile(r"^signal\s+(\w+)", re.MULTILINE)
RE_VAR_TIPADA = re.compile(r"^var\s+(\w+)\s*:\s*(\w+)", re.MULTILINE)


# Metodos heredados de Object/Node/Node3D/RefCounted que nunca se declaran
# en el script y por tanto no son errores.
METODOS_NATIVOS = {
    "new", "free", "queue_free", "duplicate", "get", "set", "has", "call",
    "callv", "call_deferred", "emit_signal", "connect", "disconnect", "is_valid",
    "is_connected", "has_method", "has_signal", "get_meta", "set_meta", "has_meta",
    "remove_meta", "add_to_group", "remove_from_group", "is_in_group",
    "add_child", "remove_child", "get_node", "get_parent", "find_child",
    "find_children", "get_owner", "set_owner", "is_inside_tree", "get_tree",
    "get_viewport", "get_world_3d", "instance_from_id", "get_instance_id",
    "notification", "to_string", "get_class", "is_class", "set_process",
    "set_physics_process", "set_process_input", "get_signal_list",
    "get_method_list", "get_property_list", "get_script", "set_script",
}


def metodos_por_clase(ficheros: list[Path]) -> dict[str, set[str]]:
    """Nombre de clase -> metodos declarados, para cruzar llamadas entre scripts."""
    salida: dict[str, set[str]] = {}
    for f in ficheros:
        texto = f.read_text(encoding="utf-8")
        m = RE_CLASS_NAME.search(texto)
        nombre = m.group(1) if m else f.stem.capitalize()
        salida[nombre] = set(RE_FUNC.findall(texto))
    return salida


SEÑALES_NATIVAS = {
    "timeout", "pressed", "toggled", "body_entered", "body_exited",
    "area_entered", "area_exited", "finished", "animation_finished",
    "value_changed", "item_selected", "text_submitted", "text_changed",
}


def senales_por_clase(ficheros: list[Path]) -> dict[str, set[str]]:
    salida: dict[str, set[str]] = {}
    for f in ficheros:
        texto = f.read_text(encoding="utf-8")
        m = RE_CLASS_NAME.search(texto)
        salida[m.group(1) if m else f.stem.capitalize()] = set(RE_SIGNAL.findall(texto))
    return salida


def comprobar_manejadores(ficheros: list[Path]) -> int:
    """`.connect(_on_algo)` donde _on_algo no esta declarado en el fichero."""
    problemas = 0
    for f in ficheros:
        texto = f.read_text(encoding="utf-8")
        declaradas = set(RE_FUNC.findall(texto))
        for i, linea in enumerate(texto.splitlines(), 1):
            if linea.lstrip().startswith("#"):
                continue
            for m in re.finditer(r"\.connect\(\s*([A-Za-z_]\w*)\s*\)", linea):
                if m.group(1) not in declaradas:
                    print(f"{f.relative_to(ROOT)}:{i}: MANEJADOR -> {m.group(1)}() no declarado")
                    problemas += 1
    return problemas


def comprobar_arrays_tipados(ficheros: list[Path]) -> int:
    """`var x: Array[T] = dicc.get(...)`: el Dictionary devuelve un Array sin
    tipo y Godot lanza error de ejecucion al asignarlo."""
    problemas = 0
    patron = re.compile(r"^\s*var\s+(\w+)\s*:\s*Array\[[^\]]+\]\s*=\s*[\w.]+\s*\.\s*get\(",
                        re.MULTILINE)
    for f in ficheros:
        for i, linea in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if linea.lstrip().startswith("#"):
                continue
            if patron.match(linea):
                print(f"{f.relative_to(ROOT)}:{i}: ARRAY -> asignacion sin copiar "
                      "(usa `x.assign(dicc.get(...))` o copia a mano)")
                problemas += 1
    return problemas


def comprobar_senales(ficheros: list[Path], senales: dict[str, set[str]]) -> int:
    """`variable.senal.connect()` sobre una clase del proyecto: la senal debe
    estar declarada en esa clase o ser nativa de Godot."""
    problemas = 0
    for f in ficheros:
        texto = f.read_text(encoding="utf-8")
        variables = [(n, t) for n, t in RE_VAR_TIPADA.findall(texto) if t in senales]
        for var, tipo in variables:
            for senal in re.findall(r"\b%s\.(\w+)\.connect\(" % re.escape(var), texto):
                if senal in senales[tipo] or senal in SEÑALES_NATIVAS:
                    continue
                print(f"{f.relative_to(ROOT)}: SENAL -> {var}: {tipo}.{senal} no declarada")
                problemas += 1
    return problemas


def comprobar_llamadas_entre_clases(ficheros: list[Path],
                                     clases: dict[str, set[str]]) -> int:
    """Detecta `variable.metodo()` donde la variable esta tipada con una clase
    del proyecto y ese metodo no existe. Es el error tipico al dividir el juego
    en varios scripts (y el unico que el parser no puede ver)."""
    problemas = 0
    for f in ficheros:
        texto = f.read_text(encoding="utf-8")
        variables = [(n, t) for n, t in RE_VAR_TIPADA.findall(texto) if t in clases]
        # tambien parametros tipados: func f(x: Clase)
        for tipo, nombre in re.findall(r"\b(\w+)\s*:\s*(\w+)\b(?=\s*[,)])", texto):
            if nombre in clases:
                variables.append((tipo, nombre))
        for var, tipo in variables:
            for metodo in re.findall(r"\b%s\.(\w+)\s*\(" % re.escape(var), texto):
                if metodo not in clases[tipo]:
                    # los metodos de Object (new, free...) no estan en la clase
                    if metodo in METODOS_NATIVOS:
                        continue
                    print(f"{f.relative_to(ROOT)}: CRUCE -> {var}: {tipo}.{metodo}() no existe")
                    problemas += 1
    return problemas


def cargar_api() -> dict:
    if not API_JSON.is_file():
        return {}
    with gzip.open(API_JSON, "rt", encoding="utf-8") as f:
        return json.load(f)


def indice_api(api: dict) -> tuple[dict, dict]:
    """Devuelve (metodos por clase con herencia, constantes por clase)."""
    if not api:
        return {}, {}
    crudo: dict[str, dict] = {}
    for c in api.get("classes", []):
        # Las constantes de un enum no van en `constants` sino en `enums`.
        constantes = {k["name"] for k in c.get("constants", [])}
        for en in c.get("enums", []):
            for v in en.get("values", []):
                constantes.add(v["name"])
        crudo[c["name"]] = {
            "metodos": {m["name"] for m in c.get("methods", [])} | {"new"},
            "constantes": constantes,
            "padre": c.get("inherits"),
        }
    resuelto: dict[str, dict] = {}

    def resolver(nombre: str) -> dict:
        if nombre in resuelto:
            return resuelto[nombre]
        datos = crudo.get(nombre)
        if datos is None:
            resuelto[nombre] = {"metodos": set(), "constantes": set()}
            return resuelto[nombre]
        metodos = set(datos["metodos"])
        constantes = set(datos["constantes"])
        padre = datos["padre"]
        if padre:
            pm = resolver(padre)
            metodos |= pm["metodos"]
            constantes |= pm["constantes"]
        resuelto[nombre] = {"metodos": metodos, "constantes": constantes}
        return resuelto[nombre]

    for nombre in list(crudo):
        resolver(nombre)
    return resuelto, crudo


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default="scripts", help="carpeta con los .gd")
    args = ap.parse_args()

    try:
        from gdtoolkit.parser import parser
    except ImportError:
        print("falta gdtoolkit:  pip install gdtoolkit", file=sys.stderr)
        return 2

    api = cargar_api()
    clases, _ = indice_api(api)
    if not api:
        print(f"aviso: no encontre {API_JSON}; solo valido sintaxis y rutas",
              file=sys.stderr)

    ficheros = sorted((ROOT / args.dir).glob("*.gd"))
    if not ficheros:
        print(f"no hay .gd en {args.dir}", file=sys.stderr)
        return 2

    problemas = 0
    for f in ficheros:
        texto = f.read_text(encoding="utf-8")
        nombre = f.relative_to(ROOT)

        # 1) sintaxis
        try:
            parser.parse(texto)
        except Exception as e:  # noqa: BLE001
            print(f"{nombre}: SINTAXIS -> {str(e).splitlines()[0]}")
            problemas += 1
            continue

        # 2) rutas de preload
        for ruta in RE_PRELOAD.findall(texto):
            destino = ROOT / ruta.replace("res://", "")
            if not destino.exists():
                print(f"{nombre}: PRELOAD -> no existe {ruta}")
                problemas += 1

        # 3) API de Godot
        if clases:
            for clase, metodo in RE_CLASE_METODO.findall(texto):
                if clase not in clases:
                    continue
                if metodo not in clases[clase]["metodos"]:
                    print(f"{nombre}: API -> {clase}.{metodo}() no existe en Godot 4.4")
                    problemas += 1
            for clase, const in RE_CLASE_CONST.findall(texto):
                if clase not in clases:
                    continue
                if const not in clases[clase]["constantes"]:
                    print(f"{nombre}: API -> {clase}.{const} no existe en Godot 4.4")
                    problemas += 1

        # 4) la clase base debe existir (o ser un script del proyecto)
        m = RE_EXTENDS.search(texto)
        if m and clases:
            base = m.group(1)
            locales = {p.stem for p in ficheros}
            nombres_clase = set(re.findall(r"^class_name\s+(\w+)", texto, re.MULTILINE))
            if base not in clases and base not in nombres_clase and base != "RefCounted":
                print(f"{nombre}: EXTENDS -> clase base desconocida '{base}'")
                problemas += 1

    # 5) llamadas entre clases del proyecto
    clases_proyecto = metodos_por_clase(ficheros)
    problemas += comprobar_llamadas_entre_clases(ficheros, clases_proyecto)

    # 6) senales declaradas antes de conectarse
    problemas += comprobar_senales(ficheros, senales_por_clase(ficheros))

    # 7) manejadores de senal y arrays tipados desde Dictionary
    problemas += comprobar_manejadores(ficheros)
    problemas += comprobar_arrays_tipados(ficheros)

    print(f"\n{len(ficheros)} scripts revisados, {problemas} problemas")
    return 0 if problemas == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
