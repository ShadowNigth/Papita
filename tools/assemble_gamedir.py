#!/usr/bin/env python3
"""Ensambla el gamedir `cstrike` que consume Xash3D a partir de assets/.

El repositorio guarda el material original en una carpeta neutra (`assets/`) y
este script lo coloca en la jerarquia exacta que espera GoldSrc:

    assets/models/cs15/p_ak47.mdl      -> cstrike/models/p_ak47.mdl
    assets/models/cs15/player/gign/... -> cstrike/models/player/gign/gign.mdl
    assets/sounds/cs15/weapons/x.wav   -> cstrike/sound/weapons/x.wav
    assets/maps/cs15/de_dust2.bsp      -> cstrike/maps/de_dust2.bsp

Ademas escribe liblist.gam y los .cfg del preset "CS 1.5" desde config/.
El resultado (game/) es descartable: se regenera con este script.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
MDL = ASSETS / "models" / "cs15"
WAV = ASSETS / "sounds" / "cs15"
MAPS = ASSETS / "maps" / "cs15"
CONFIG = ROOT / "config"

CT = ("urban", "gsg9", "sas", "gign")
T = ("terror", "leet", "arctic", "guerilla")

# GoldSrc resuelve por ruta y en Linux distingue mayusculas en algunos sitios:
# los sonidos de interfaz viven en sound/UI y el resto en minusculas.
SOUND_DIR_CASE = {"ui": "UI"}

# Archivos que el juego pide siempre y que NO estan en el repositorio: son del
# Half-Life base (valve/) o del cliente de Counter-Strike. Se avisa de ellos.
BASE_REQUIRED = [
    ("valve/gfx/palette.lmp", "paleta de 256 colores: sin ella los .bsp se ven mal"),
    ("valve/gfx.wad", "fuente de consola (gfx/conchars)"),
    ("valve/sprites/*.spr", "humps, humo, shadow_circle... los usa el game dll"),
    ("valve/models/hgibs.mdl", "gibs de sangre"),
    ("valve/models/*gibs.mdl", "gibs de material (cristal, metal, madera)"),
]


def log(msg: str) -> None:
    print(f"\033[1;36m[gamedir]\033[0m {msg}")


def warn(msg: str) -> None:
    print(f"\033[1;33m[gamedir]\033[0m {msg}", file=sys.stderr)


def asegurar(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def copiar(src: Path, dst: Path, usar_enlaces: bool) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.is_symlink() or dst.exists():
        dst.unlink()
    if usar_enlaces:
        try:
            os.link(src, dst)  # ahorra 60 MB de copia en el mismo disco
            return
        except OSError:
            pass
    shutil.copy2(src, dst)


def ensamblar_modelos(dst: Path, enlaces: bool) -> int:
    n = 0
    out = asegurar(dst / "models")
    for mdl in sorted(MDL.glob("*.mdl")):
        if mdl.name == "hostage.mdl":
            continue  # va a models/player/hostage
        copiar(mdl, out / mdl.name, enlaces)
        n += 1

    for faction in CT + T + ("vip",):
        src = MDL / "player" / faction / f"{faction}.mdl"
        if not src.is_file():
            warn(f"falta el modelo de faccion {faction}")
            continue
        copiar(src, out / "player" / faction / f"{faction}.mdl", enlaces)
        n += 1

    rehen = MDL / "hostage.mdl"
    if rehen.is_file():
        copiar(rehen, out / "player" / "hostage" / "hostage.mdl", enlaces)
        n += 1
    return n


def aliasar_viewmodels(cstrike: Path) -> int:
    """Crea v_<arma>.mdl a partir de los v_<arma>_r.mdl originales del 1.5.

    El game dll moderno precachea `models/v_ak47.mdl`, mientras que los assets
    de CS 1.5 se llaman `v_ak47_r.mdl` (variante "right hand"). El modelo es el
    mismo, solo cambia el nombre: aliasar evita ~30 errores de precache por mapa.
    """
    out = cstrike / "models"
    n = 0
    for src in sorted(out.glob("v_*_r.mdl")):
        alias = out / (src.name[:-6] + ".mdl")  # v_x_r.mdl -> v_x.mdl
        if alias.exists():
            continue
        try:
            os.link(src, alias)
        except OSError:
            shutil.copy2(src, alias)
        n += 1

    # El servidor busca el rehen en models/hostage.mdl ademas de player/hostage/.
    rehen = out / "player" / "hostage" / "hostage.mdl"
    destino = out / "hostage.mdl"
    if rehen.is_file() and not destino.exists():
        try:
            os.link(rehen, destino)
        except OSError:
            shutil.copy2(rehen, destino)
        n += 1
    return n


def ensamblar_sonidos(dst: Path, enlaces: bool) -> int:
    n = 0
    out = asegurar(dst / "sound")
    for carpeta in sorted(p for p in WAV.iterdir() if p.is_dir()):
        destino = out / SOUND_DIR_CASE.get(carpeta.name, carpeta.name)
        for wav in sorted(carpeta.glob("*.wav")):
            copiar(wav, destino / wav.name, enlaces)
            n += 1
    return n


def ensamblar_mapas(dst: Path, enlaces: bool) -> int:
    out = asegurar(dst / "maps")
    mapas = sorted(MAPS.glob("*.bsp"))
    for bsp in mapas:
        copiar(bsp, out / bsp.name, enlaces)
    return len(mapas)


def escribir_texto(dst: Path, nombre: str, contenido: str) -> None:
    ruta = dst / nombre
    ruta.parent.mkdir(parents=True, exist_ok=True)
    # Los .cfg de GoldSrc se leen byte a byte: CRLF y ASCII/UTF-8 sin BOM.
    ruta.write_bytes(contenido.replace("\n", "\r\n").encode("utf-8"))


def instalar_config(dst: Path, realmlib: Path | None) -> int:
    n = 0
    for archivo in sorted(CONFIG.glob("*")):
        if archivo.is_file():
            escribir_texto(dst, archivo.name, archivo.read_text(encoding="utf-8"))
            n += 1

    # ReGameDLL publica en dist/ los ficheros de red y los .cfg base del mod.
    if realmlib:
        dist = realmlib / "dist"
        for nombre in ("delta.lst", "game.cfg", "game_init.cfg"):
            src = dist / nombre
            if src.is_file():
                copiar(src, dst / nombre, False)
                n += 1
    if not (dst / "delta.lst").is_file():
        warn("falta delta.lst: pasa --regamedll .src/ReGameDLL_CS (el servidor no arranca sin el)")
    return n


def instalar_dll(dst: Path, dll: Path | None) -> None:
    if not dll:
        return
    if not dll.is_file():
        warn(f"no existe el game dll {dll}")
        return
    # El motor añade el sufijo de arquitectura (_amd64) al nombre de liblist.gam.
    destino = dst / "dlls" / "cs_amd64.so"
    if dll.name.endswith("_amd64.so") or dll.name == "cs.so":
        destino = dst / "dlls" / dll.name
    destino.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(dll, destino)
    log(f"game dll -> dlls/{destino.name}")


def instalar_valve(game: Path, base: Path, enlaces: bool) -> None:
    destino = game / "valve"
    if destino.is_symlink() or destino.exists():
        if destino.is_symlink():
            destino.unlink()
        elif base.resolve() != destino.resolve():
            shutil.rmtree(destino)
    if destino.exists():
        log("valve/ ya enlazado")
        return
    try:
        destino.symlink_to(base.resolve(), target_is_directory=True)
        log(f"valve/ -> {base} (enlace simbolico)")
    except OSError:
        shutil.copytree(base, destino)
        log(f"valve/ copiado desde {base}")


def informe(game: Path) -> None:
    faltan = []
    for rel, motivo in BASE_REQUIRED:
        if "*" in rel:
            if not list(game.glob(rel)):
                faltan.append((rel, motivo))
        elif not (game / rel).exists():
            faltan.append((rel, motivo))
    if faltan:
        warn("recursos base que el juego pedira y no estan:")
        for rel, motivo in faltan:
            print(f"    - {rel:32s} {motivo}")
        print("    (opcion 1: tools/bootstrap_valve.py con tu instalacion legal de Half-Life)")
        print("    (opcion 2: tools/make_free_base.py para un base libre de pruebas)")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="game", help="carpeta de salida (por defecto game/)")
    ap.add_argument("--dll", help="ruta a cs_amd64.so compilado")
    ap.add_argument("--regamedll", help="checkout de ReGameDLL_CS (para dist/)")
    ap.add_argument("--valve", help="carpeta valve/ de tu Half-Life (recursos base)")
    ap.add_argument("--copy", action="store_true",
                    help="copiar en vez de usar enlaces duros")
    ap.add_argument("--clean", action="store_true", help="borrar la salida antes")
    args = ap.parse_args()

    game = (ROOT / args.out).resolve() if not Path(args.out).is_absolute() else Path(args.out)
    cstrike = game / "cstrike"
    if args.clean and cstrike.exists():
        # Solo se limpia el gamedir; game/valve (recursos base, enlazados a tu
        # instalacion de Half-Life) se conserva.
        log(f"limpiando {cstrike}")
        shutil.rmtree(cstrike)

    if not MDL.is_dir():
        print(f"error: no existe {MDL}", file=sys.stderr)
        return 1

    enlaces = not args.copy
    cstrike.mkdir(parents=True, exist_ok=True)

    n_mdl = ensamblar_modelos(cstrike, enlaces)
    n_alias = aliasar_viewmodels(cstrike)
    n_wav = ensamblar_sonidos(cstrike, enlaces)
    n_bsp = ensamblar_mapas(cstrike, enlaces)
    realmlib = Path(args.regamedll).resolve() if args.regamedll else None
    n_cfg = instalar_config(cstrike, realmlib)
    instalar_dll(cstrike, Path(args.dll).resolve() if args.dll else None)
    if args.valve:
        instalar_valve(game, Path(args.valve), enlaces)

    log(f"{n_mdl} modelos (+{n_alias} aliases), {n_wav} sonidos, {n_bsp} mapas, "
        f"{n_cfg} ficheros de config")
    log(f"gamedir listo en {cstrike}")
    informe(cstrike)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
