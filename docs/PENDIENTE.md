# Qué falta, por orden de importancia

Lista honesta de lo que no está hecho o no está probado. Ordenada por lo que más
se nota al abrir el juego.

## 1. Que arranque en Godot (bloqueante)

El proyecto **no se ha ejecutado nunca**. Se escribió en un entorno sin Godot
(GitHub Releases bloqueado, sin forma de descargar el editor), y se validó de
forma estática: sintaxis con `gdtoolkit`, API contra el volcado de Godot 4.4 y
la lógica de parseo replicada en Python contra los assets reales.

Lo más probable que haya que tocar en la primera ejecución:

- **Nombres de señales del HUD**: `hud.gd` accede a `jugador._retroceso`, un
  miembro privado. Funciona, pero es feo: convendría una señal.
- **El atlas de luz**: si un mapa tiene muchas caras con lightmap, el atlas
  puede quedarse corto (se detiene en 4096×4096 y las caras sobrantes quedan a
  luz plena). Se nota como zonas "quemadas".
- **`SurfaceTool.generate_normals()`** en caras degeneradas puede avisar.
- **Rendimiento del atlas**: se generan ~5000 caras por mapa con llamadas
  `set_pixel` una a una. `de_nuke` (7670 caras) puede tardar segundos. La
  solución es volcar el lightmap a `PackedByteArray` y crear la `Image` de una
  vez.

## 2. Animaciones: hechas, pero sin mezcla

El decodificador y el skinning están terminados y verificados (ver
`docs/ANIMACIONES.md`): las secuencias se reproducen con los datos originales.

Lo que falta para que se vean *bien* en juego:

- **Mezcla (blending) de 9 blends de arma**: `ref_aim_ak47` tiene `numblends=9`
  (una pose por arma). Ahora mismo se usa el blend 0, así que el soldado sujeta
  el arma en la pose genérica, no la del arma que lleva.
- **Transiciones suaves** entre secuencias: ahora el cambio es instantáneo
  (`cambiar de walk a idle` salta). Falta interpolar entre poses 0,1-0,3 s.
- **Eventos de animación** (`mstudioevent_t`): el motor los usa para disparar
  sonidos de paso y destellos de boca de cañón en el cuadro exacto.
- **`linear movement`** (desplazamiento de raíz) para animaciones de muerte.

## 3. Bots

Los actores que deambulan por el mapa **no son IA**: se mueven en línea recta
entre puntos de aparición y pueden atravesar paredes. No hay navegación. `legacy/xash/` sí los tenía (los de ReGameDLL); aquí habría que
escribir navegación propia. La opción razonable es usar los `clipnodes` y las
hojas del `.bsp` para construir un grafo de puntos de navegación, en vez de
inventar un NavMesh sobre geometría ya particionada.

Desde el modo de juego sí hacen de **contrario**: tienen vida, reciben daño,
mueren, sueltan el cadáver y la ronda se cierra cuando no queda ninguno vivo.
Lo que no hacen: disparar al jugador ni moverse con criterio.

## 4. Granadas y C4

La C4 **está implementada** (`scripts/bomb.gd`): se planta manteniendo `E`
durante 3 s dentro de un `func_bomb_target`, cuenta atrás de 35 s con pitidos
que se aceleran, luz roja intermitente y explosión de 200 de daño a menos de
12,5 m. Se desactiva manteniendo `E` 10 s (5 s con kit) y el progreso se pierde
al soltar.

Las **granadas** siguen sin lanzarse. Ahora se compran, se cuentan aparte
(`player.granadas`, máximo 4 de cada tipo) y no se "equipan" como arma, pero no
hay proyectil. Falta:

- Física de proyectil (`RigidBody3D` con rebote, `he_bounce1.wav`).
- Explosión con daño radial y caída por distancia.
- Flashbang: cegado por línea de visión y ángulo.
- Humo (`smokegrenade`).

## 5. Modo de juego

Hecho (`scripts/match_director.gd`, `economy.gd`, `buy_menu.gd`): congelación,
rondas de 5 minutos, marcador, economía con bono de derrota, menú de compra con
teclas numéricas, victoria por eliminación / tiempo / bomba. **Sin ejecutar.**

Lo que falta o está a medias:

- **Equipos**: hay dos bandos, pero el jugador es el único que juega. No existe
  spawn por equipo real: los `info_player_start` del `.bsp` son genéricos y se
  reaparece siempre en el primer punto guardado.
- **Rehenes**: `cs_office` y `cs_italy` tienen `hostage_entity` y
  `func_hostage_rescue`; se leen las zonas pero no hay lógica de rehenes
  (`CsEconomy` ya tiene el importe del rescate).
- **Bots que disparen**: ver §3.
- **Mitad de tiempo / cambio de bando** (`mp_halftime`).
- **Pausa de compra fuera de la congelación**: en el original se puede comprar
  también el primer segundo y medio de la ronda; aquí solo en congelación.
- **`mp_maxrounds`** existe en el código (`--rondas N`), pero no hay pantalla de
  fin de partida: solo un mensaje de texto.
- **Cuchillo cuerpo a cuerpo**: `knife` tiene ficha en `weapon_db.gd`, pero no
  hay animación de ataque ni `trace` corto; dispara como si fuera un arma.

## 6. La paleta

Los colores no son los de 1999 porque falta `palette.lmp` (ver README §5).
No es un bug: es un asset que no se puede redistribuir. Con tu copia legal de
Half-Life se resuelve copiando el fichero.

## 7. Detalles del original que faltan

- Sprites (`.spr`): miras, humo, sangre, iconos del HUD. No están en `assets/`.
- Sonidos ambientales por mapa (`ambient_generic` en las entidades).
- Puertas y `func_door`: se leen las entidades pero no se crean.
- `func_breakable` y cristales.
- Escaleras (`func_ladder`).
- Niebla y cielo por mapa (`light_environment` se lee, pero de forma básica).
- Bots de radio y mensajes de texto del HUD.

## Lo que sí está terminado y verificado

- Lectura de los 15 lumps del `.bsp` en los 10 mapas, sin errores.
- Lectura de mallas, huesos y texturas en los 96 modelos, sin errores.
- Animación de esqueleto (RLE + slerp + skinning GPU) y 215 secuencias
  comprobadas con movimiento real.
- Render de validación (planos de mapas y vistas de modelos) en `docs/previews/`.
- Comprobación de la API de Godot 4.4 en los 16 scripts, incluidas las llamadas
  y señales entre clases del propio proyecto (`tools/gdscript_check.py`).
- Constantes, precios y aritmética del modo de juego contrastados con el 1.5 y
  economía simulada en 200 rondas (`tools/partida_validate.py`).
