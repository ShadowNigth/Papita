# Compilar y ejecutar

Todo lo que hay que hacer, de cero a jugar, y los problemas que aparecen por el
camino (todos los de aquí me pasaron de verdad al montarlo).

## 0. Requisitos

**Para el servidor dedicado** (mínimo, sin ventana):

- Linux x86-64 (probado en Debian 12), macOS o Windows con MSYS2/WSL
- `gcc`/`g++` con C11 y C++17, `make`, `python3` (3.10+), `git`
- `cmake` 3.20+ (para ReGameDLL y cs16-client). Si tu distro trae uno viejo:
  `pip install cmake`
- ~2 GB de disco para `.src/` y `.build/`

**Para el cliente con vídeo**, además:

- `libsdl2-dev`, `libgl1-mesa-dev`, `pkg-config`
- una GPU con OpenGL 2.1+ (o `ref_soft`, el renderizador por software)

## 1. Todo de una vez

```bash
./tools/build_all.sh
```

Si algo falla, ve a la sección 6: cada error está explicado.

## 2. Paso a paso

```bash
# 1) fuentes en revisiones fijas (.src/)
./tools/fetch_sources.sh

# 2) motor, servidor dedicado -> runtime/xash
./tools/build_engine.sh dedicated

# 3) game dll -> .build/regamedll/regamedll/cs_amd64.so
./tools/build_gamedll.sh

# 4) gamedir jugable -> game/cstrike/
python3 tools/assemble_gamedir.py \
    --dll .build/regamedll/regamedll/cs_amd64.so \
    --regamedll .src/ReGameDLL_CS

# 5) recursos base: elige UNA
python3 tools/bootstrap_valve.py --source "$HOME/.steam/steam/steamapps/common/Half-Life/valve"
#   o, si no tienes Half-Life a mano, un base libre para probar:
python3 tools/make_free_base.py

# 6) comprobar
./tools/smoke_test.sh
```

## 3. Jugar

```bash
./run_server.sh de_dust2        # servidor dedicado (27015/udp)
./run_client.sh                 # cliente con ventana (si lo compilaste)
```

En el cliente, la consola (`~`) sigue siendo la de siempre: `map de_inferno`,
`bot_add`, `bot_quota 8`, `nav_generate`, `changelevel de_nuke`...

## 4. Cliente con vídeo

```bash
sudo apt install libsdl2-dev libgl1-mesa-dev pkg-config
./tools/build_engine.sh client
./tools/build_client.sh
./run_client.sh
```

`build_client.sh` compila `cs16-client` y copia `client_amd64.so` y
`menu_amd64.so` a `runtime/`. `run_client.sh` los enlaza dentro de
`game/cstrike/cl_dll/`.

## 5. Plataformas y 32/64 bits

El proyecto compila **64 bits** de punta a punta. Es la única combinación que
verifiqué; si prefieres 32 bits necesitas multilib (`gcc-multilib`) y compilar
ReGameDLL **sin** `-DXASH_COMPAT=ON`.

En Windows el flujo es equivalente desde MSYS2 (`pacman -S mingw-w64-x86_64-{gcc,cmake,SDL2}`),
sustituyendo `.so` por `.dll`; `liblist.gam` ya declara las tres variantes.

## 6. Problemas conocidos (y su causa real)

**`build.h: No such file or directory`** al compilar el motor.
Xash3D incluye `build.h` en casi todos sus headers, pero ese archivo no está
versionado: lo genera su CI. `tools/gen_build_h.py` lo crea con los macros de
plataforma correctos (arquitectura, endianness, SO).

**`#error` en `3rdparty/library_suffix/include/buildenums.h`**.
Mismo motivo: faltan `XASH_AMD64`/`XASH_X86`, `XASH_LINUX`, `XASH_LITTLE_ENDIAN`.
Los pone el mismo script.

**`Can't find libbacktrace submodule` / `mbedtls` / `library_suffix`.**
`git submodule update` no sirve aquí: bzip2 vive en gitlab.com, que algunas redes
bloquean. `fetch_sources.sh` clona cada submódulo desde su URL de GitHub
declarada en `pins.lock` (bzip2 desde el espejo `libarchive/bzip2`).

**`bits/libc-header-start.h: No such file or directory`** al compilar el game dll.
ReGameDLL intenta `-m32` cuando ve un host de 64 bits. Solución: configurar con
`-DXASH_COMPAT=ON` (`build_gamedll.sh` ya lo hace).

**`CMake Error ... Compatibility with CMake < 3.5 has been removed`.**
CMake 4 contra proyectos que declaran `cmake_minimum_required(3.1)`. Se pasa
`-DCMAKE_POLICY_VERSION_MINIMUM=3.5`, como hacen los scripts.

**`can't load filesystem_stdio.so`**.
Xash necesita esa librería **junto al ejecutable**, no en el gamedir.
`build_engine.sh` la copia a `runtime/`.

**`can't initialize dlls/cs_amd64_amd64.so`**.
El motor añade el sufijo `_amd64` a lo declarado en `liblist.gam`. Si ahí pone
`cs_amd64`, busca `cs_amd64_amd64`. Correcto: `gamedll "dlls/cs.so"` con el
fichero llamado `cs_amd64.so`.

**`Host_InitCommon: couldn't load gfx.wad`**.
No es el WAD: el motor comprueba `FS_FileExists("gfx/conchars")`. Sin
`game/valve` con `gfx/conchars` (o un `gfx.wad` que lo contenga) aborta.
Solución: `bootstrap_valve.py` o `make_free_base.py`.

**`Delta_InitFields: couldn't load file delta.lst`**.
ReGameDLL necesita `delta.lst`, `game.cfg` y `game_init.cfg` de su carpeta
`dist/`. `assemble_gamedir.py` los copia si le pasas `--regamedll`.

**`Could not load model models/v_ak47.mdl`** (y 30 más).
Los assets de 1.5 se llaman `v_ak47_r.mdl`; el game dll precachea sin `_r`. El
ensamblador crea los alias automáticamente.

**`Could not load model sprites/*.spr` o `models/hgibs.mdl`**.
Son recursos del Half-Life base, no del repositorio. Ver
[`ASSETS.md`](ASSETS.md#lo-que-falta).
