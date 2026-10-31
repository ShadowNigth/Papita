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

    print(f"\n{len(ficheros)} scripts revisados, {problemas} problemas")
    return 0 if problemas == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
