# Aviso legal

## Marcas y propiedad intelectual

**Counter-Strike**, **Half-Life** y sus logotipos son marcas registradas de
**Valve Corporation**. Este proyecto no está afiliado, patrocinado ni aprobado
por Valve.

## Los assets NO son libres

Los ficheros de `assets/` son material original del juego:

- `assets/models/cs15/**` — 96 modelos `.mdl`
- `assets/maps/cs15/**` — 10 mapas `.bsp`
- `assets/sounds/cs15/**` — 352 sonidos `.wav`

Pertenecen a Valve Corporation. **No** están cubiertos por la GPLv3 del
repositorio, **no** se distribuyen con él y **no** deben incluirse en zips,
binarios, repositorios públicos ni releases que se compartan.

Se mantienen en local, procedentes de una copia legítima del juego, con fines de
homenaje técnico y estudio personal.

## Qué sí se publica

- El código de `tools/`, `config/` y la documentación: **GPLv3** (`LICENSE`).
- Las instrucciones para compilar dependencias libres (Xash3D-FWGS GPLv3,
  ReGameDLL_CS MIT, cs16-client GPLv2+).
- Una base mínima **generada desde cero** (`tools/make_free_base.py`): paleta
  aproximada y fuente de 8x8 dibujada a mano. No contiene material de Valve.

## Qué NO se publica

- Los assets de `assets/`.
- Cualquier copia de `game/` (contiene los assets reorganizados y, si usas
  `bootstrap_valve.py`, enlaces a tu Half-Life).
- `runtime/` con binarios compilados (puedes compilarlos tú: es software libre,
  pero nada obliga a redistribuirlos).

## Dependencias

Cada dependencia conserva su licencia: ver [`NOTICE.md`](../NOTICE.md). Que este
repositorio sea GPLv3 no cambia la licencia del motor ni de la game dll.

## Si no tienes el juego

Sin una licencia legítima de Counter-Strike 1.5 / Half-Life no tienes derecho a
usar los assets de este repositorio. El código y el motor sí puedes usarlos
bajo sus licencias, pero sin assets no hay juego.
