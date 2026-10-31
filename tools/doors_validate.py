#!/usr/bin/env python3
"""Valida los brush models móviles de puerta contra los `.bsp` reales.

No ejecuta Godot: comprueba rangos de caras/modelos, que las caras de cada
puerta se puedan separar de la malla estática y que `angle`/`angles`, `lip` y
`speed` produzcan recorridos finitos y positivos. También verifica los puntos
de integración entre MapBuilder, BspReader y MapDoor.

    python3 tools/doors_validate.py
"""
from __future__ import annotations

import math
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cs15_validate import MAPS, ROOT, Bsp, cargar_paleta  # noqa: E402

DOORS = {"func_door", "func_door_rotating"}


def modelos_bsp(bsp: Bsp) -> list[dict]:
    ofs, ln = bsp.lumps[14]
    modelos = []
    for i in range(ln // 64):
        base = ofs + i * 64
        mn = np.asarray(struct.unpack_from("<3f", bsp.raw, base), dtype=np.float64)
        mx = np.asarray(struct.unpack_from("<3f", bsp.raw, base + 12), dtype=np.float64)
        first, count = struct.unpack_from("<ii", bsp.raw, base + 56)
        modelos.append({"min": mn, "max": mx, "first": first, "count": count})
    return modelos


def direccion_lineal(entidad: dict) -> np.ndarray:
    if "angle" in entidad:
        angulo = float(entidad["angle"])
        if math.isclose(angulo, -1.0):
            return np.array((0.0, 0.0, 1.0))
        if math.isclose(angulo, -2.0):
            return np.array((0.0, 0.0, -1.0))
        rad = math.radians(angulo)
        return np.array((math.cos(rad), math.sin(rad), 0.0))
    if "angles" in entidad:
        pitch, yaw, _roll = (math.radians(float(x)) for x in entidad["angles"].split())
        return np.array((math.cos(pitch) * math.cos(yaw),
                         math.cos(pitch) * math.sin(yaw), -math.sin(pitch)))
    return np.array((1.0, 0.0, 0.0))


def validar_mapa(path: Path, paleta) -> tuple[dict, list[str]]:
    bsp = Bsp(path, paleta)
    modelos = modelos_bsp(bsp)
    mundo = modelos[0]
    fin_mundo = mundo["first"] + mundo["count"]
    caras_movil = set()
    rangos_puerta = []
    errores = []
    contadores = {"func_door": 0, "func_door_rotating": 0}

    for entidad in bsp.entidades:
        clase = entidad.get("classname", "")
        if clase not in DOORS:
            continue
        contadores[clase] += 1
        modelo_txt = entidad.get("model", "")
        if not modelo_txt.startswith("*"):
            errores.append(f"{clase}: falta model brush")
            continue
        indice = int(modelo_txt[1:])
        if indice <= 0 or indice >= len(modelos):
            errores.append(f"{clase} {modelo_txt}: indice de modelo fuera de rango")
            continue
        modelo = modelos[indice]
        first, count = modelo["first"], modelo["count"]
        end = first + count
        if first < 0 or count <= 0 or end > len(bsp.face_texinfo):
            errores.append(f"{clase} {modelo_txt}: rango de caras invalido")
            continue
        if first < fin_mundo and end > mundo["first"]:
            errores.append(f"{clase} {modelo_txt}: sus caras se solapan con el mundo")
        if any(first < b and end > a for a, b in rangos_puerta):
            errores.append(f"{clase} {modelo_txt}: rango de caras duplicado")
        rangos_puerta.append((first, end))
        caras_movil.update(range(first, end))

        vertices = [bsp.vertices_cara(i) for i in range(first, end)
                    if bsp.face_numedges[i] >= 3]
        if not vertices:
            errores.append(f"{clase} {modelo_txt}: sin vertices de cara")
            continue
        puntos = np.concatenate(vertices, axis=0)
        if not np.isfinite(puntos).all():
            errores.append(f"{clase} {modelo_txt}: vertices no finitos")
            continue
        vmin, vmax = puntos.min(axis=0), puntos.max(axis=0)
        if np.any(vmin < modelo["min"] - 1e-3) or np.any(vmax > modelo["max"] + 1e-3):
            errores.append(f"{clase} {modelo_txt}: la caja no contiene sus caras")

        texturas_visibles = 0
        for cara in range(first, end):
            ti = int(bsp.face_texinfo[cara])
            if not 0 <= ti < len(bsp.tex_miptex):
                continue
            tex = int(bsp.tex_miptex[ti])
            if not 0 <= tex < len(bsp.texturas):
                continue
            nombre = bsp.texturas[tex]["nombre"].lower()
            if not nombre.startswith(("sky", "trigger", "clip", "origin",
                                      "aaatrigger", "hint", "skip")):
                texturas_visibles += 1
        if texturas_visibles == 0:
            errores.append(f"{clase} {modelo_txt}: no tiene caras renderizables")

        velocidad = float(entidad.get("speed", "100"))
        if not math.isfinite(velocidad) or velocidad <= 0.0:
            errores.append(f"{clase} {modelo_txt}: velocidad invalida ({velocidad})")
        if clase == "func_door":
            dir_gs = direccion_lineal(entidad)
            if int(entidad.get("spawnflags", "0")) & 2:
                dir_gs = -dir_gs
            lip = float(entidad.get("lip", "0"))
            distancia = float(np.abs(dir_gs) @ (modelo["max"] - modelo["min"]) - lip)
            if not math.isfinite(distancia) or abs(distancia) < 1.0:
                errores.append(f"{clase} {modelo_txt}: recorrido casi nulo/invalido ({distancia})")
        else:
            giro = float(entidad.get("distance", "90"))
            if not math.isfinite(giro) or abs(giro) < 1.0 or abs(giro) > 360.0:
                errores.append(f"{clase} {modelo_txt}: giro invalido ({giro})")
            if "origin" not in entidad:
                errores.append(f"{clase} {modelo_txt}: falta pivot origin")

    world_faces = set(range(mundo["first"], fin_mundo))
    if caras_movil & world_faces:
        errores.append("hay caras de puertas incluidas en el rango del mundo")

    return ({"mapa": path.stem,
             "sliding": contadores["func_door"],
             "rotating": contadores["func_door_rotating"],
             "doors": sum(contadores.values()),
             "faces": len(caras_movil)}, errores)


def validar_integracion() -> list[str]:
    errores = []
    builder = (ROOT / "scripts" / "map_builder.gd").read_text(encoding="utf-8")
    reader = (ROOT / "scripts" / "bsp_reader.gd").read_text(encoding="utf-8")
    door = (ROOT / "scripts" / "map_door.gd").read_text(encoding="utf-8")
    for fragmento in ("_caras_de_puertas", "_agrupar_rango", "MapDoor.new()",
                      "ConcavePolygonShape3D", "caras_dinamicas"):
        if fragmento not in builder:
            errores.append(f"MapBuilder no integra {fragmento}")
    for fragmento in ("modelos_primera_cara", "modelos_num_caras"):
        if fragmento not in reader:
            errores.append(f"BspReader no guarda {fragmento}")
    for fragmento in ("class_name MapDoor", "func configurar(", "body_entered",
                      "body_exited", "func activar(", "sync_to_physics",
                      "FLAG_START_OPEN", "FLAG_REVERSE_DIRECTION", "FLAG_PASSABLE",
                      "FLAG_NO_AUTO_RETURN"):
        if fragmento not in door:
            errores.append(f"MapDoor no implementa {fragmento}")
    return errores


def main() -> int:
    paleta, origen = cargar_paleta()
    print(f"paleta: {origen}\n")
    print(f"{'mapa':12} {'corredizas':>10} {'giratorias':>10} {'caras':>7}")
    total_puertas = total_caras = errores = 0
    for path in sorted(MAPS.glob("*.bsp")):
        r, fallos = validar_mapa(path, paleta)
        total_puertas += r["doors"]
        total_caras += r["faces"]
        print(f"{r['mapa']:12} {r['sliding']:10d} {r['rotating']:10d} {r['faces']:7d}")
        for fallo in fallos:
            errores += 1
            print(f"    !! {fallo}")
    for fallo in validar_integracion():
        errores += 1
        print(f"!! {fallo}")
    print(f"\npuertas con brush separado: {total_puertas} entidades, {total_caras} caras")
    print(f"problemas: {errores}")
    return 1 if errores else 0


if __name__ == "__main__":
    sys.exit(main())
