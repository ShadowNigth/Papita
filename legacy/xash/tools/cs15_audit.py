#!/usr/bin/env python3
"""Audita los assets originales de Counter-Strike 1.5 del repositorio.

Comprueba, leyendo los binarios y sin depender de Godot ni del motor:

  * .mdl  StudioModel v10: magic, version, texturas embebidas, huesos, secuencias
  * .bsp  GoldSrc v30: los 15 lumps, entidades jugables, miptex embebidas o en WAD
  * .wav  RIFF/WAVE: formato, canales, frecuencia y duracion

Salida legible por humanos y, con --json, un informe para maquinas.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import wave
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MDL_DIR = ROOT / "assets" / "models" / "cs15"
MAP_DIR = ROOT / "assets" / "maps" / "cs15"
SOUND_DIR = ROOT / "assets" / "sounds" / "cs15"

BSP_LUMPS = [
    "entidades", "planos", "texturas", "vertices", "visibilidad", "nodos",
    "texinfo", "caras", "iluminacion", "clipnodes", "hojas", "marksurfaces",
    "aristas", "surfedtas", "modelos",
]
# Entidades sin las que un mapa no es jugable en el modo que promete el nombre.
REQUIRED_ENTS = {
    "de_": ("func_bomb_target", "info_player_start", "info_player_deathmatch"),
    "cs_": ("hostage_entity", "info_player_start", "info_player_deathmatch"),
}


def leer_mdl(path: Path) -> dict:
    b = path.read_bytes()
    if len(b) < 244:
        raise ValueError("fichero demasiado corto")
    ident = b[0:4].decode("latin1")
    ver = struct.unpack("<i", b[4:8])[0]
    nombre = b[8:72].split(b"\0")[0].decode("latin1")
    # studiohdr_t: numbones@140 boneindex@144 ... numseq@164 seqindex@168
    # numtextures@180 textureindex@184 texturedataindex@188 numbodyparts@204
    numbones, boneidx = struct.unpack("<ii", b[140:148])
    numseq, seqidx = struct.unpack("<ii", b[164:172])
    numtex, texidx = struct.unpack("<ii", b[180:188])
    texturedata = struct.unpack("<i", b[188:192])[0]
    numbodyparts = struct.unpack("<i", b[204:208])[0]
    texturas = []
    if 0 < numtex < 64 and 0 <= texidx < len(b):
        for i in range(numtex):
            base = texidx + i * 80
            if base + 80 > len(b):
                break
            tname = b[base:base + 64].split(b"\0")[0].decode("latin1")
            flags, wid, hei = struct.unpack("<iii", b[base + 64:base + 76])
            idx = struct.unpack("<i", b[base + 76:base + 80])[0]
            # textureindex guarda el offset ABSOLUTO al bloque de la textura
            # dentro del fichero (no es relativo a texturedataindex).
            embebida = 0 < idx < len(b)
            texturas.append({"nombre": tname, "ancho": wid, "alto": hei,
                             "flags": flags, "embebida": embebida})
    return {
        "fichero": path.name,
        "ident": ident,
        "version": ver,
        "nombre_interno": nombre,
        "texturas": texturas,
        "huesos": numbones,
        "secuencias": numseq,
        "partes_cuerpo": numbodyparts,
        "bytes": len(b),
        "ok": ident == "IDST" and ver == 10 and all(t["embebida"] for t in texturas),
    }


def leer_bsp(path: Path) -> dict:
    b = path.read_bytes()
    ver = struct.unpack("<i", b[0:4])[0]
    lumps = [struct.unpack("<ii", b[4 + i * 8:12 + i * 8]) for i in range(15)]
    invalidos = [BSP_LUMPS[i] for i, (o, l) in enumerate(lumps)
                 if o < 0 or l < 0 or o + l > len(b)]

    eofs, elen = lumps[0]
    texto = b[eofs:eofs + elen].split(b"\0")[0].decode("latin1", "replace")
    ents, cur = [], {}
    for linea in texto.split("\n"):
        linea = linea.strip()
        if linea == "{":
            cur = {}
        elif linea == "}":
            if cur:
                ents.append(cur)
        elif linea.startswith('"'):
            trozos = linea.split('"')
            if len(trozos) >= 4:
                cur[trozos[1]] = trozos[3]
    clases = Counter(e.get("classname", "?") for e in ents)

    tofs, tlen = lumps[2]
    miptex, embebidas, externas = [], 0, 0
    if tlen >= 4:
        n = struct.unpack("<i", b[tofs:tofs + 4])[0]
        if 0 < n < 4096 and tofs + 4 + n * 4 <= len(b):
            for off in struct.unpack("<%di" % n, b[tofs + 4:tofs + 4 + 4 * n]):
                base = tofs + off
                if base + 28 > len(b):
                    continue
                nombre = b[base:base + 16].split(b"\0")[0].decode("latin1")
                o1 = struct.unpack("<i", b[base + 24:base + 28])[0]
                miptex.append(nombre)
                if o1 == -1:
                    externas += 1
                else:
                    embebidas += 1

    prefijo = path.stem[:3]
    exigidas = REQUIRED_ENTS.get(prefijo, ())
    faltan = [e for e in exigidas if clases.get(e, 0) == 0]

    return {
        "fichero": path.name,
        "version": ver,
        "bytes": len(b),
        "lumps_invalidos": invalidos,
        "entidades": len(ents),
        "clases": dict(clases.most_common()),
        "miptex": len(miptex),
        "miptex_embebidas": embebidas,
        "miptex_externas": externas,
        "faltan_entidades": faltan,
        "ok": ver == 30 and not invalidos and not faltan,
    }


def leer_wav(path: Path) -> dict:
    with wave.open(str(path), "rb") as w:
        frames = w.getnframes()
        rate = w.getframerate()
        return {
            "fichero": str(path.relative_to(SOUND_DIR)),
            "canales": w.getnchannels(),
            "bits": w.getsampwidth() * 8,
            "hz": rate,
            "segundos": round(frames / rate, 3) if rate else 0.0,
            "bytes": path.stat().st_size,
        }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", help="escribir informe JSON en esta ruta")
    ap.add_argument("--quiet", action="store_true", help="solo el resumen")
    args = ap.parse_args()

    informe: dict = {"modelos": [], "mapas": [], "sonidos": [], "errores": []}

    print("== MODELOS (.mdl StudioModel v10) ==")
    for p in sorted(MDL_DIR.rglob("*.mdl")):
        try:
            d = leer_mdl(p)
        except Exception as e:  # noqa: BLE001
            informe["errores"].append(f"{p.name}: {e}")
            continue
        informe["modelos"].append(d)
        if not args.quiet:
            tex = ", ".join(t["nombre"] for t in d["texturas"]) or "-"
            estado = "ok" if d["ok"] else "REVISAR"
            print(f"  {d['fichero']:28s} v{d['version']:<3d} tex={len(d['texturas'])} "
                  f"huesos={d['huesos']:<3d} seq={d['secuencias']:<3d} {estado} [{tex}]")

    print("\n== MAPAS (.bsp GoldSrc v30) ==")
    for p in sorted(MAP_DIR.glob("*.bsp")):
        try:
            d = leer_bsp(p)
        except Exception as e:  # noqa: BLE001
            informe["errores"].append(f"{p.name}: {e}")
            continue
        informe["mapas"].append(d)
        if not args.quiet:
            print(f"  {d['fichero']:16s} ents={d['entidades']:<4d} miptex={d['miptex']:<4d} "
                  f"(emb={d['miptex_embebidas']}, wad={d['miptex_externas']}) "
                  f"{'ok' if d['ok'] else 'REVISAR ' + str(d['faltan_entidades'])}")

    print("\n== SONIDOS (.wav) ==")
    for p in sorted(SOUND_DIR.rglob("*.wav")):
        try:
            informe["sonidos"].append(leer_wav(p))
        except Exception as e:  # noqa: BLE001
            informe["errores"].append(f"{p.name}: {e}")

    sonidos = informe["sonidos"]
    total_seg = sum(s["segundos"] for s in sonidos)
    if sonidos:
        hz = Counter(s["hz"] for s in sonidos).most_common(3)
        canales = Counter(s["canales"] for s in sonidos).most_common()
        bits = Counter(s["bits"] for s in sonidos).most_common()
        if not args.quiet:
            print(f"  {len(sonidos)} ficheros, {total_seg:.1f} s en total")
        print(f"  frecuencias: {hz}")
        print(f"  canales: {canales}  bits: {bits}")

    print("\n== RESUMEN ==")
    malos_mdl = [m["fichero"] for m in informe["modelos"] if not m["ok"]]
    malos_bsp = [m["fichero"] for m in informe["mapas"] if not m["ok"]]
    print(f"  modelos: {len(informe['modelos'])} ({len(malos_mdl)} con avisos)")
    print(f"  mapas:   {len(informe['mapas'])} ({len(malos_bsp)} con avisos)")
    print(f"  sonidos: {len(sonidos)}")
    if informe["errores"]:
        print(f"  errores de lectura: {len(informe['errores'])}")
        for e in informe["errores"][:5]:
            print(f"    - {e}")

    if args.json:
        Path(args.json).write_text(json.dumps(informe, indent=2, ensure_ascii=False))
        print(f"  informe JSON: {args.json}")

    return 0 if not (malos_mdl or malos_bsp or informe["errores"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
