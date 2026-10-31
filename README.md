# PAPITA · Counter-Strike 1.5 sobre Xash3D-FWGS

Recreación jugable de **Counter-Strike 1.5** usando el **motor real de GoldSrc**
(Xash3D-FWGS) en lugar de un motor propio, con los **96 modelos StudioModel v10**,
los **352 sonidos** y los **10 mapas `.bsp` v30** originales que ya viven en
`assets/`.

Esto no es un clon aproximado: el motor carga los `.bsp`, `.mdl` y `.wav` tal
como los guardaba Valve en 2002. La geometría, las texturas embebidas, los
lightmaps, los huesos, las animaciones y los sonidos son los de siempre.

> **Estado: verificado hasta donde se puede en un entorno sin pantalla.**
> El servidor dedicado se compila y arranca, el game dll carga y **los 10 mapas
> llegan a "player server started"** con sus entidades (`func_bomb_target`,
> `hostage_entity`, `func_buyzone`, 20 spawns). Lo que no se ha podido probar
> aquí es el cliente con ventana (no hay SDL2/OpenGL en el entorno de
> compilación); compilarlo es cosa de tu máquina, ver [`docs/COMPILAR.md`](docs/COMPILAR.md).

---

## 1. Qué hay dentro

| Pieza | Repositorio | Licencia | Estado |
|---|---|---|---|
| Motor | [FWGS/xash3d-fwgs](https://github.com/FWGS/xash3d-fwgs) `a7becfd` | GPLv3 | compilado y ejecutado |
| Reglas (game dll) | [s1lentq/ReGameDLL_CS](https://github.com/s1lentq/ReGameDLL_CS) `4a50c42` | MIT | compilado, 64 bits con `XASH_COMPAT` |
| Cliente (HUD, menús) | [Velaron/cs16-client](https://github.com/Velaron/cs16-client) `a238ef1` | GPLv2+ | receta lista, sin compilar aquí |
| Recursos base libres | [FWGS/xash-extras](https://github.com/FWGS/xash-extras) | GPLv3 | usado para `cacert.pem` y fuentes |
| Assets del juego | Material original de CS 1.5 en `assets/` | Propiedad de Valve | **local, no se redistribuye** |

Las revisiones exactas están en [`engine/pins.lock`](engine/pins.lock); nada se
trae de una rama móvil.

## 2. Arranque rápido

```bash
./tools/build_all.sh          # fuentes -> motor -> game dll -> gamedir -> prueba
./run_server.sh de_dust2      # servidor dedicado en el puerto 27015
```

`build_all.sh` hace, en orden:

1. `tools/fetch_sources.sh` — clona las dependencias en `.src/` y las deja en el
   commit exacto de `pins.lock`.
2. `tools/build_engine.sh dedicated` — compila el motor con waf y deja
   `runtime/xash` + `runtime/filesystem_stdio.so`.
3. `tools/build_gamedll.sh` — compila `cs_amd64.so` con CMake.
4. `tools/assemble_gamedir.py` — coloca los assets en `game/cstrike/`.
5. `tools/make_free_base.py` — genera un `game/valve/` mínimo y libre (paleta y
   fuente propias) para poder arrancar sin Half-Life.
6. `tools/smoke_test.sh` — arranca cada mapa y comprueba que el servidor queda
   operativo.

Para jugar con **vídeo** hace falta además el cliente:

```bash
sudo apt install libsdl2-dev libgl1-mesa-dev   # o el equivalente de tu distro
./tools/build_engine.sh client
./tools/build_client.sh
./run_client.sh
```

## 3. El gamedir

`game/cstrike/` es **generado**, no versionado. Se rehace con
`tools/assemble_gamedir.py`:

```
assets/models/cs15/p_ak47.mdl       -> cstrike/models/p_ak47.mdl
assets/models/cs15/v_ak47_r.mdl     -> cstrike/models/v_ak47_r.mdl
                                       cstrike/models/v_ak47.mdl     (alias)
assets/models/cs15/player/gign/*    -> cstrike/models/player/gign/gign.mdl
assets/models/cs15/hostage.mdl      -> cstrike/models/hostage.mdl
assets/sounds/cs15/weapons/*.wav    -> cstrike/sound/weapons/*.wav
assets/sounds/cs15/ui/*.wav         -> cstrike/sound/UI/*.wav
assets/maps/cs15/de_dust2.bsp       -> cstrike/maps/de_dust2.bsp
```

Detalles que costaron encontrar y quedan resueltos en el ensamblador:

- El motor **añade el sufijo de arquitectura** al game dll: `liblist.gam` dice
  `dlls/cs.so` y en 64 bits busca `dlls/cs_amd64.so`.
- Los assets de 1.5 se llaman `v_ak47_r.mdl` pero el game dll moderno precachea
  `v_ak47.mdl`: se crean 26 alias (mismo inodo, coste cero).
- `sound/ui` pasa a `sound/UI` por la sensibilidad a mayúsculas del sistema de
  ficheros de GoldSrc.

## 4. Verificación incluida

```bash
python3 tools/cs15_audit.py          # valida los binarios de assets/
./tools/smoke_test.sh                # arranca el servidor con los 10 mapas
```

Resultados reales en este repositorio:

```
modelos: 96 (0 con avisos)   mapas: 10 (0 con avisos)   sonidos: 352
OK  cs_assault / cs_estate / cs_italy / cs_office
OK  de_aztec / de_dust / de_dust2 / de_inferno / de_nuke / de_train
10 mapas OK, 0 con fallo
```

`cs15_audit.py` no se fía del README: lee los binarios y comprueba el magic
`IDST`/versión 10 de los `.mdl` (con sus texturas embebidas), los 15 lumps y las
entidades jugables de los `.bsp`, y el formato RIFF de los 352 `.wav`.

## 5. Lo que falta y se nota

Honestidad por delante, porque son las cosas que vas a ver al primer arranque:

1. **Recursos del Half-Life base.** El motor pide `valve/gfx.wad`,
   `valve/gfx/palette.lmp`, sprites de efectos (`sprites/*.spr`) y gibs
   (`models/hgibs.mdl`, `*gibs.mdl`). No están en el repositorio ni deben
   redistribuirse. Dos salidas:
   ```bash
   python3 tools/bootstrap_valve.py --source "/ruta/Half-Life/valve"   # fiel
   python3 tools/make_free_base.py                                     # paleta propia
   ```
   Con la base libre los mapas cargan, pero los colores no son los de 1999
   porque la paleta de 256 colores es una aproximación generada.
2. **Reglas 1.6.** ReGameDLL implementa el 1.6. `config/server.cfg` fija los
   valores del 1.5 (35 s de C4, 15 s de compra, 800 $ iniciales, física de
   800/10/10...) pero el menú de compra del cliente sí ofrece **FAMAS, Galil y
   escudo**, que en 1.5 no existían: al comprarlos fallará el modelo, porque no
   hay `models/p_famas.mdl` ni `models/p_galil.mdl`. No se inventan: se avisa.
3. **Sprites del HUD.** Los iconos de arma, el radar y el humo son `.spr` del
   CS original, que no están en `assets/`. Sin ellos la consola avisa y el HUD
   pierde iconos.
4. **Cliente sin probar aquí.** `cs16-client` necesita SDL2 y OpenGL; este
   entorno no los tiene. La receta está escrita y es la misma que usa la
   comunidad, pero no la he ejecutado.
5. **Bots.** ReGameDLL trae los bots de CS integrados (`bot_add`, `bot_quota`)
   pero **no** hay ficheros `.nav` por mapa: hay que ejecutar `nav_generate`
   una vez por mapa desde el juego.

## 6. Estructura

```
assets/                modelos, sonidos y mapas originales (material de Valve)
config/                liblist.gam, server.cfg, autoexec.cfg, config.cfg...
engine/pins.lock       revisión exacta de cada dependencia
tools/                 fetch, build, assemble, audit, smoke test, bootstrap
runtime/               binarios compilados (generado)
game/                  gamedir cstrike + valve (generado)
docs/                  compilación, assets, arquitectura, aviso legal
legacy/godot/          la versión anterior del proyecto, en Godot 4
```

`legacy/godot/` conserva íntegro el intento previo (34 scripts GDScript,
~20 500 líneas, shaders y loaders propios). No se borró porque es trabajo real y
sirve de referencia, pero **no es el proyecto activo**.

## 7. Documentación

- [`docs/COMPILAR.md`](docs/COMPILAR.md) — requisitos, compilación paso a paso, problemas conocidos.
- [`docs/ASSETS.md`](docs/ASSETS.md) — qué asset hay, qué formato tiene y de dónde falta.
- [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md) — cómo encajan motor, game dll, cliente y gamedir.
- [`docs/AVISO_LEGAL.md`](docs/AVISO_LEGAL.md) — licencias y por qué los assets no se publican.

## 8. Licencia

El **código propio** de este repositorio (scripts de `tools/`, configuración y
documentación) se publica bajo **GPLv3** (ver [`LICENSE`](LICENSE)), en
coherencia con Xash3D-FWGS. Cada dependencia mantiene su licencia, resumida en
[`NOTICE.md`](NOTICE.md).

Los **assets** (`.mdl`, `.bsp`, `.wav`) son propiedad de Valve Corporation y
**no** están cubiertos por esa licencia ni se distribuyen con el proyecto.
