#!/usr/bin/env python3
"""Enlaza (o copia) los recursos base de TU instalacion legal de Half-Life.

Counter-Strike 1.5 no es un juego autonomo: reutiliza del Half-Life base la
paleta, la fuente de consola, sprites de efectos, gibs y sonidos comunes. El
repositorio NO los incluye y no deben redistribuirse.

    python3 tools/bootstrap_valve.py --source "/ruta/Half-Life/valve"

Busca en la carpeta indicada los ficheros imprescindibles y avisa de los que
falten. Nunca descarga nada: solo opera sobre archivos que ya tienes.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

IMPRESCINDIBLES = [
    "gfx.wad",
    "gfx/palette.lmp",
]
RECOMENDADOS = [
    "sprites",
    "models/hgibs.mdl",
    "models/agibs.mdl",
    "sound/player/pl_pain2.wav",
]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True, help="carpeta valve/ de tu Half-Life")
    ap.add_argument("--out", default="game/valve", help="destino (por defecto game/valve)")
    ap.add_argument("--copy", action="store_true", help="copiar en vez de enlazar")
    args = ap.parse_args()

    origen = Path(args.source).expanduser().resolve()
    destino = (ROOT / args.out).resolve()

    if not (origen / "gfx.wad").is_file():
        print(f"error: {origen} no parece un gamedir valve/ (falta gfx.wad)", file=sys.stderr)
        return 1

    faltan = [f for f in IMPRESCINDIBLES if not (origen / f).exists()]
    if faltan:
        print(f"aviso: faltan en el origen: {', '.join(faltan)}", file=sys.stderr)

    if destino.is_symlink():
        destino.unlink()
    elif destino.exists():
        print(f"{destino} ya existe (borralo si quieres reenlazarlo)")
        return 0

    destino.parent.mkdir(parents=True, exist_ok=True)
    if args.copy:
        shutil.copytree(origen, destino)
        modo = "copiado"
    else:
        try:
            destino.symlink_to(origen, target_is_directory=True)
            modo = "enlazado"
        except OSError:
            shutil.copytree(origen, destino)
            modo = "copiado (sin permisos de enlace)"

    print(f"{destino} {modo} desde {origen}")
    for f in RECOMENDADOS:
        if not (origen / f).exists():
            print(f"  aviso: tu copia no tiene {f}")
    print("Listo. Ahora: ./run_client.sh")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
