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
- `assets/valve/**` — si copias aquí `palette.lmp` o `gfx.wad`

Pertenecen a Valve Corporation. **No** están cubiertos por la GPLv3 del
repositorio, **no** se distribuyen con él y **no** deben incluirse en zips,
binarios ni releases que se compartan.

## Qué sí se publica

- Los scripts de `scripts/`, `shaders/`, `tools/` y la documentación: **GPLv3**.
- Las capturas de `docs/previews/`: son renders de *mis* lectores de formato,
  no ficheros del juego.

## Qué NO se publica

- Los assets de `assets/` (ver arriba).
- `game/`, `runtime/`, `.src/` y `.build/`: están en `.gitignore`.

## Sobre Godot

Godot Engine es software libre bajo licencia **MIT** (© Juan Linietsky, Ariel
Manzur y colaboradores). Este repositorio no incluye binarios de Godot.

## La versión anterior

`legacy/xash/` compila y ejecuta **Xash3D-FWGS** (GPLv3) y **ReGameDLL_CS**
(MIT). Cada dependencia conserva su licencia; ver `legacy/xash/NOTICE.md`.

## Si no tienes el juego

Sin una licencia legítima de Counter-Strike 1.5 / Half-Life no tienes derecho a
usar los assets de este repositorio. El código y los scripts sí puedes usarlos
bajo la GPLv3, pero sin assets no hay juego.
