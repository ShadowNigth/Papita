# Los assets: qué hay, en qué formato y qué falta

Todo lo que sigue está comprobado leyendo los binarios con
`python3 tools/cs15_audit.py` (no con lo que diga un README antiguo).

## Modelos — `assets/models/cs15/` (96 ficheros, 26 MB)

Formato **StudioModel v10** (`IDST`), el de GoldSrc. Todos con texturas
embebidas (BMP de 8 bits en el propio `.mdl`), así que no necesitan WADs.

| Grupo | Cantidad | Ejemplos | Uso |
|---|---|---|---|
| `v_*_r.mdl` | 28 | `v_ak47_r.mdl`, `v_knife_r.mdl` | arma en primera persona |
| `p_*.mdl` | 28 | `p_glock18.mdl`, `p_c4.mdl` | arma en la mano del soldado |
| `w_*.mdl` | 30 | `w_mp5.mdl`, `w_kevlar.mdl` | arma en el suelo |
| `player/<faccion>` | 9 | `gign`, `sas`, `urban`, `terror`, `leet`, `arctic`, `guerilla`, `vip` | soldados |
| `hostage.mdl` | 1 | - | rehén |
| `skeleton.mdl` | 1 | - | esqueleto de referencia |

Los modelos de soldado tienen 53-55 huesos y animaciones completas (correr,
agacharse, disparar, morir, recargar); los de arma, 1 hueso y una secuencia. Los
nombres internos delatan su origen (`gign\gign.mdl`, `ak47/v_ak47_r.mdl`).

Detalle: varios viewmodels son de la hornada de **CS 1.6** (`uspnew/v_usp_r.mdl`,
`m3_new/v_m3_r.mdl`, `sog2000/v_sog2000_r.mdl`). Se ven prácticamente igual que
los de 1.5, pero conviene saberlo si comparas capturas.

## Mapas — `assets/maps/cs15/` (10 ficheros, 25 MB)

Formato **GoldSrc v30** (`.bsp`), con los **15 lumps válidos** y, esto es lo
importante, **texturas embebidas** (no hace falta ningún `.wad`):

| Mapa | Entidades | Texturas | Modo |
|---|---|---|---|
| `de_dust2` | 101 | 44 | bomba |
| `de_dust` | 106 | 30 | bomba |
| `de_inferno` | 125 | 75 | bomba |
| `de_nuke` | 218 | 156 | bomba |
| `de_train` | 129 | 112 | bomba |
| `de_aztec` | 107 | 41 | bomba |
| `cs_office` | 245 | 214 | rehenes |
| `cs_italy` | 178 | 102 | rehenes |
| `cs_assault` | 163 | 182 | rehenes |
| `cs_estate` | 238 | 147 | rehenes |

Los mapas de bomba traen `func_bomb_target` y los de rehenes `hostage_entity`,
más `func_buyzone`, `info_player_start`/`info_player_deathmatch` (10-20 por
mapa), `func_breakable`, `ambient_generic`, `func_door`... Es decir: son
jugables de verdad, no decorado.

## Sonidos — `assets/sounds/cs15/` (352 ficheros, 6.8 MB)

RIFF/WAVE, **mono**, 8 bits salvo uno, casi todo a 22050 Hz (85 a 11025 Hz):

| Carpeta | Ficheros | Contenido |
|---|---|---|
| `weapons` | 162 | cada disparo, recarga, corredera y golpe, por arma |
| `player` | 79 | pasos por material, dolor, muerte, caída, respiración |
| `radio` | 43 | radio de equipo ("Go go go", "Bomb has been planted"...) |
| `zombie` | 16 | gruñidos y golpes (resto de mods) |
| `items` | 12 | recogida, chaleco, linterna, NVG |
| `ambience` | 9 | viento, agua, truenos, grillos |
| `common` | 9 | selección de arma, bodydrops, HUD |
| `debris` | 9 | cristal, madera, metal rompiéndose |
| `ui` | 7 | menús |
| `hostage` | 5 | rehenes |
| `doors` | 1 | puerta |

Total: unos 30 minutos de audio original.

## Lo que falta

Ninguno de estos está en el repositorio. Los tres primeros son del Half-Life
base (se resuelven con `tools/bootstrap_valve.py`); el resto es del cliente.

| Falta | Dónde vive | Efecto |
|---|---|---|
| `gfx/palette.lmp` | `valve/` | sin paleta, los `.bsp` no se pueden colorear |
| `gfx.wad` (lump `conchars`) | `valve/` | el motor se niega a arrancar |
| `sprites/*.spr` (38) | `valve/` | humo, chispas, sangre, iconos del HUD |
| `models/*gibs.mdl` (10) | `valve/` | gibs al morir |
| `models/grenade.mdl`, `models/chick.mdl` | `valve/` | granada genérica, gallina |
| `models/p_famas.mdl`, `p_galil.mdl`, `p_shield.mdl`, `v_shield.mdl` | CS 1.6 | armas que **no existían en 1.5** |
| `resource/`, `gfx/vgui/` | cliente CS | menús VGUI del cliente |

Tras ensamblar el gamedir y con la base libre, el servidor arranca con ~113
avisos de este tipo en `de_dust2`; con el `valve/` real de Half-Life bajan a
solo las armas 1.6.

## Integridad

`tools/cs15_audit.py --json informe.json` deja un informe con, por fichero:
versión, texturas, huesos, secuencias, lumps, entidades, duración y formato de
audio. Úsalo para detectar un asset corrupto antes de culpar al motor.
