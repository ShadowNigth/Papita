#!/usr/bin/env python3
"""Genera un `valve/` minimo y LIBRE para poder arrancar el motor sin Half-Life.

Xash3D aborta si no encuentra `gfx/conchars` y los .bsp necesitan una paleta de
256 colores para sus texturas indexadas. Sin una instalacion legal de Half-Life
no hay `gfx.wad` ni `palette.lmp`, asi que este script fabrica unos propios:

  * `gfx/palette.lmp`  cubo 6x6x6 + rampa de grises (768 bytes)
  * `gfx/conchars`     fuente 128x128 indexada, glifos dibujados aqui
  * `cacert.pem`, `*.fnt`, `gamecontrollerdb.txt` desde xash-extras

AVISO: la paleta es aproximada. Los mapas cargan y se juega, pero los colores
de las texturas originales NO son los de 1999. Para eso hay que usar
`tools/bootstrap_valve.py` con una copia legal de Half-Life.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Glifos 8x8 dibujados como cadenas de bits: punto = pixel encendido.
FONT_BITS = {
    "A": ("..###...", ".##.##..", "##...##.", "##...##.", "#######.", "##...##.", "##...##.", "........"),
    "B": ("######..", "##...##.", "##...##.", "######..", "##...##.", "##...##.", "######..", "........"),
    "C": (".#####..", "##...##.", "##......", "##......", "##......", "##...##.", ".#####..", "........"),
    "?": (".#####..", "##...##.", "....##..", "...##...", "...##...", "........", "...##...", "........"),
    " ": ("........",) * 8,
}


def paleta() -> bytes:
    """768 bytes RGB. Cubo 6x6x6 (216) + 40 grises, igual que un VGA tipico."""
    out = bytearray()
    for r in range(6):
        for g in range(6):
            for b in range(6):
                out += bytes((r * 51, g * 51, b * 51))
    for i in range(40):
        v = min(255, i * 255 // 39)
        out += bytes((v, v, v))
    return bytes(out[:768])


def conchars() -> bytes:
    """128x128 indexado: 16x16 celdas de 8x8. Indice 0 = transparente."""
    img = bytearray(128 * 128)
    for ch, filas in FONT_BITS.items():
        celda = ord(ch)
        cx, cy = (celda % 16) * 8, (celda // 16) * 8
        for y, fila in enumerate(filas):
            for x, bit in enumerate(fila):
                if bit == ".":
                    continue
                img[(cy + y) * 128 + (cx + x)] = 255
    # Caracteres de control y bloque relleno: marco tenue para depurar el HUD.
    for celda in range(256):
        if chr(celda) in FONT_BITS:
            continue
        cx, cy = (celda % 16) * 8, (celda // 16) * 8
        for i in range(8):
            img[(cy) * 128 + (cx + i)] = 128
            img[(cy + 7) * 128 + (cx + i)] = 128
    return bytes(img)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="game/valve", help="carpeta valve/ a crear")
    ap.add_argument("--force", action="store_true", help="sobrescribir si ya existe")
    args = ap.parse_args()

    valve = (ROOT / args.out).resolve()
    gfx = valve / "gfx"
    if (gfx / "palette.lmp").exists() and not args.force:
        print(f"{valve} ya tiene base; usa --force para regenerarla")
        return 0

    gfx.mkdir(parents=True, exist_ok=True)
    (gfx / "palette.lmp").write_bytes(paleta())
    (gfx / "conchars").write_bytes(conchars())

    extras = (Path(__import__("os").environ.get("PAPITA_SRC", ROOT / ".src"))
              / "xash3d-fwgs" / "3rdparty" / "extras" / "xash-extras")
    copiados = 0
    if extras.is_dir():
        for patron in ("*.fnt", "cacert.pem", "gamecontrollerdb.txt"):
            for f in extras.glob(patron):
                (valve / f.name).write_bytes(f.read_bytes())
                copiados += 1
    else:
        print(f"aviso: no encontre xash-extras en {extras}", file=sys.stderr)

    print(f"base libre en {valve}")
    print(f"  gfx/palette.lmp  {len(paleta())} bytes")
    print(f"  gfx/conchars     {128 * 128} bytes (fuente 8x8 propia)")
    print(f"  {copiados} recursos de xash-extras")
    print("Recuerda: paleta aproximada; para colores fieles usa tools/bootstrap_valve.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
