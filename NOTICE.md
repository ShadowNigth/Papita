# Atribuciones y licencias

Este repositorio combina piezas con licencias distintas. Este documento dice
cuál es cada una y qué se puede hacer con ella.

## Código y scripts de este repositorio

`tools/*`, `config/*`, `docs/*`, `README.md` -> **GNU GPL v3**
(texto completo en [`LICENSE`](LICENSE)).

## Dependencias compiladas en tiempo de build

No se copia su código aquí: `tools/fetch_sources.sh` las clona en `.src/` en la
revisión exacta de `engine/pins.lock`.

| Proyecto | Autoría | Licencia | Copia de la licencia |
|---|---|---|---|
| [Xash3D-FWGS](https://github.com/FWGS/xash3d-fwgs) | Uncle Mike, FWGS y colaboradores | GPLv3 | `LICENSE` |
| [ReGameDLL_CS](https://github.com/s1lentq/ReGameDLL_CS) | ReGameDLL_CS Contributors | MIT | [`docs/LICENSE-ReGameDLL-MIT.txt`](docs/LICENSE-ReGameDLL-MIT.txt) |
| [cs16-client](https://github.com/Velaron/cs16-client) | Flying With Gauss | GPLv2+ | [`docs/LICENSE-cs16-client-GPL2.txt`](docs/LICENSE-cs16-client-GPL2.txt) |
| [xash-extras](https://github.com/FWGS/xash-extras) | FWGS | GPLv3 | - |
| libbacktrace, mbedtls, miniz, libogg, vorbis, opus, opusfile, mpg123, bzip2 | varios | BSD/Apache/zlib/MIT | en sus repos |

ReGameDLL_CS pasó a MIT en 2025 (`LICENSE-TRANSITION.md` en su repositorio);
las versiones anteriores eran GPLv3.

## Recursos generados por los scripts

- `game/valve/gfx/palette.lmp` y `game/valve/gfx/conchars` los produce
  `tools/make_free_base.py` desde cero: son obra derivada de este repositorio y
  caen bajo GPLv3. Su paleta es una aproximación, no la de Half-Life.
- `game/cstrike/` es una reorganización de `assets/` (ver abajo), no obra nueva.

## Assets del juego (NO libres)

`assets/models/cs15/**`, `assets/maps/cs15/**`, `assets/sounds/cs15/**` son
material original de **Counter-Strike 1.5 / Half-Life**, propiedad de **Valve
Corporation**.

- No están cubiertos por la GPLv3 de este repositorio.
- No deben redistribuirse, publicarse ni incluirse en binarios o zips que se
  compartan.
- Se mantienen en local, procedentes de una copia legítima del juego, y se usan
  como homenaje técnico y personal.
- Si no tienes licencia legítima de Counter-Strike 1.5, no tienes derecho a
  usarlos.

## Fuentes tipográficas

`assets/fonts/DejaVu*` — licencia Bitstream Vera / dominio público modificado,
ver `assets/fonts/LICENSE-DejaVu.txt`. Solo las usa el proyecto antiguo de
`legacy/godot/`.
