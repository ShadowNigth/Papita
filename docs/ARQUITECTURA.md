# Arquitectura

## Idea

El proyecto anterior (`legacy/godot/`) reimplementaba Counter-Strike en Godot:
20 500 líneas de GDScript con loaders propios de `.mdl` y `.bsp`. Funcionaba,
pero era una interpretación: geometría procedural, texturas generadas, balística
aproximada.

Esta versión cambia el enfoque: **no se reimplementa el motor, se usa uno**.
Xash3D-FWGS es una reimplementación libre y compatible de GoldSrc; cargando los
archivos originales dentro de él se obtiene el juego real, no una aproximación.

```
                    ┌──────────────────────────────┐
   assets/  ───────►│  game/cstrike/  (gamedir)    │
   (.mdl .bsp .wav) │  models/ sound/ maps/ *.cfg  │
                    └───────────┬──────────────────┘
                                │ lo lee
                    ┌───────────▼──────────────────┐
                    │  runtime/xash (Xash3D-FWGS)  │  motor: BSP, MDL, red, física
                    └───────────┬──────────────────┘
                    carga ┌─────┴──────┐
                          ▼            ▼
                 dlls/cs_amd64.so   cl_dll/client_amd64.so
                 (ReGameDLL: reglas) (cs16-client: HUD, menús, predicción)
```

## Quién hace qué

**El motor** (`xash3d-fwgs`): parsea `.bsp` v30 (lumps, lightmaps, entidades,
PVS), `.mdl` v10 (huesos, secuencias, texturas, eventos), sirve los `.wav`,
gestiona red, física de jugadores, predicción y el sistema de ficheros virtual.

**El game dll** (`ReGameDLL_CS`, `cs_amd64.so`): las reglas. Economía, compra,
rondas, C4, rehenes, daño, bot integrado. Es el equivalente a `mp.dll`.

**El client dll** (`cs16-client`): lo que ve el jugador. HUD, menús, selección de
equipo, viewmodel con animaciones, `cl_*`.

**`liblist.gam`** es el contrato entre los tres: nombre del juego, versión y ruta
del game dll.

## Por qué 64 bits y `XASH_COMPAT`

Xash3D-FWGS compila a 64 bits con `./waf configure -8`. Para que ReGameDLL
produzca un `.so` compatible hay que configurarlo con `-DXASH_COMPAT=ON`:
cambia el ABI a 64 bits y añade el sufijo `_amd64` al nombre de la librería
(sale `cs_amd64.so`). El motor, por su parte, añade ese sufijo a lo que lea en
`liblist.gam`; de ahí la combinación `gamedll "dlls/cs.so"` + fichero
`cs_amd64.so` que parece un error y no lo es.

## Los scripts

| Script | Entrada | Salida |
|---|---|---|
| `fetch_sources.sh` | `engine/pins.lock` | `.src/` con 3 repos + submódulos |
| `gen_build_h.py` | arquitectura del host | `.src/xash3d-fwgs/public/build.h` |
| `build_engine.sh` | `.src/xash3d-fwgs` | `runtime/xash`, `filesystem_stdio.so` |
| `build_gamedll.sh` | `.src/ReGameDLL_CS` | `cs_amd64.so` |
| `build_client.sh` | `.src/cs16-client` | `client_*.so`, `menu_*.so` |
| `assemble_gamedir.py` | `assets/`, `config/` | `game/cstrike/` |
| `make_free_base.py` | nada | `game/valve/` libre (paleta + fuente) |
| `bootstrap_valve.py` | tu Half-Life | `game/valve/` enlazado |
| `cs15_audit.py` | `assets/` | validación + JSON |
| `smoke_test.sh` | `runtime/`, `game/` | 10 mapas arrancados o error |

Nada de esto se versiona: `.src/`, `.build/`, `runtime/` y `game/` están en
`.gitignore`. El repositorio solo guarda código, configuración, documentación y
los assets originales.

## Decisiones

- **Revisiones fijas, no ramas.** `pins.lock` evita que una actualización del
  motor rompa el build sin avisar.
- **Assets fuera del gamedir.** Se guardan en `assets/` con nombres neutros y el
  ensamblador los reubica; así se pueden reorganizar sin tocar los binarios.
- **Enlaces duros, no copias.** `assemble_gamedir.py` enlaza para no duplicar
  60 MB en disco (`--copy` si tu sistema de ficheros no lo permite).
- **El gamedir es desechable.** Siempre se puede borrar y regenerar; nada único
  vive en `game/`.
- **`legacy/godot/` se conserva.** Es el intento anterior, íntegro, por si sirve
  de referencia o de comparación.
