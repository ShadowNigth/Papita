# Qué falta, por orden de importancia

Lista honesta de lo que no está hecho o no está probado. Ordenada por lo que más
se nota al abrir el juego.

## 1. Validar el arranque y una partida en Godot (bloqueante)

El usuario ya inició el proyecto en Godot 4.7.2 y fue reportando errores de
parseo y ejecución durante la carga; se corrigieron los hallazgos informados,
pero aún falta confirmar una partida completa y el comportamiento de juego.
Este entorno del agente no trae Godot y la descarga de Releases redirige a un
host fuera de su lista de descargas permitidas. Se agregó
`.github/workflows/godot-ci.yml`: cada push/PR ejecuta el arranque headless y
los validadores estáticos. La primera corrida en GitHub Actions
([41164562715](https://github.com/ShadowNigth/Papita/actions/runs/41164562715))
pasó en 50 s; queda pendiente la prueba interactiva de una partida completa.

Aspectos que aún requieren una prueba funcional completa:

- **Nombres de señales del HUD**: `hud.gd` accede a `jugador._retroceso`, un
  miembro privado. Funciona, pero es feo: convendría una señal.
- **El atlas de luz**: si un mapa tiene muchas caras con lightmap, el atlas
  puede quedarse corto (se detiene en 4096×4096 y las caras sobrantes quedan a
  luz plena). Se nota como zonas "quemadas".
- **`SurfaceTool.generate_normals()`** en caras degeneradas puede avisar.
- **Puertas móviles**: aún hay que comprobar en Godot la sincronización de
  `AnimatableBody3D`, sus colisiones y la detección por proximidad.
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

Hecho (`scripts/bot_ai.gd` + `scripts/nav_grid.gd`): los bots **ven** (campo de
visión + rayo de línea de visión), **apuntan** con el error del arma y de la
dificultad, **disparan** en ráfagas, recargan, se mueven de lado en combate y
**navegan** por un grafo extraído del árbol BSP. Se inició el juego en Godot,
pero todavía no se ha validado una partida completa ni el comportamiento de
los bots; la prueba headless de inicio está automatizada en GitHub Actions. En
Python se ha validado el grafo, las transiciones de escaleras y el modelo de
puntería; no equivale a probar una partida.

Las escaleras de mano (`func_ladder`) tienen soporte **parcial**: de 34 triggers
repartidos por los mapas, 20 forman una subida validada en `cs_assault`,
`cs_estate`, `de_inferno`, `de_nuke` y `de_train`. Se buscan nodos de suelo en
los dos extremos, se comprueba el cuerpo y la cabeza a lo largo de la columna y
se conserva un waypoint vertical para que el bot suba/baje a 2,2 m/s. Los otros
14 triggers se omiten si ya caen en el mismo componente o si el BSP no ofrece
rellanos y columna libres que pasen las comprobaciones. La validación verifica
las entradas, los tramos verticales y las salidas en ambos sentidos; aún falta
verlo funcionar con el motor y las colisiones reales.

Lo que sigue faltando:

- **Saltos**: no se salta sobre cajas ni huecos. El porcentaje del grafo
  alcanzable desde alguno de los spawns varía entre 47,1 % (`cs_italy`) y
  95,4 % (`cs_estate`); las partes desconectadas incluyen tejados, toldos y
  cornisas, y no todas tienen una escalera utilizable.
- **Puertas**: `func_door` y `func_door_rotating` ya se separan de la malla
  estática y se mueven con su colisión. Se abren automáticamente al acercarse
  jugador o bot; aún no se procesan botones, `target`/`targetname`, bloqueos ni
  la bandera de “solo usar”. El grafo de navegación no modela estados de puerta.
- **Granadas** y cuchillo: no los usan.
- **Oído**: solo reaccionan a lo que ven. No oyen pasos y, aunque el bot dispara
  con sonido, no se avisan entre ellos.
- **Trabajo en equipo**: dos bots no se coordinan ni cubren ángulos distintos.
- **Rehenes**: no los escoltan ni los recogen (`cs_office`, `cs_italy`).
- **No distinguen cabeza del cuerpo**: el daño que hacen es plano y el que
  reciben es plano × 1,6 (`actor_model.gd`, que tampoco separa zonas).
- **Ajuste fino**: los números de puntería salen de simulación, no de jugar. Es
  lo primero que habrá que retocar cuando se pueda pulsar F5.

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

- **Equipos**: hay dos bandos y bots, pero el jugador sigue reapareciendo en el
  primer punto guardado; falta un spawn de jugador configurable por equipo.
- **Rehenes**: `cs_office` y `cs_italy` tienen `hostage_entity` y
  `func_hostage_rescue`; se leen las zonas pero no hay lógica de rehenes
  (`CsEconomy` ya tiene el importe del rescate).
- **Prueba de los bots en el motor**: la IA está escrita, pero falta abrir el
  proyecto en Godot y comprobar una partida real; ver §3.
- **Mitad de tiempo / cambio de bando** (`mp_halftime`).
- **Pausa de compra fuera de la congelación**: en el original se puede comprar
  también el primer segundo y medio de la ronda; aquí solo en congelación.
- **`mp_maxrounds`** existe en el código (`--rondas N`), pero no hay pantalla de
  fin de partida: solo un mensaje de texto.
- **Cuchillo cuerpo a cuerpo**: `knife` tiene ficha en `weapon_db.gd`, pero no
  hay animación de ataque ni `trace` corto; dispara como si fuera un arma.

## 6. La paleta

Los colores de las texturas del mapa no son los de 1999 porque falta
`palette.lmp` (ver README §5). No es un bug de lectura: es un asset que no se
redistribuye. Con una copia propia de Half-Life se resuelve copiando el fichero.
Las texturas de los modelos `.mdl` sí usan su paleta RGB embebida.

## 7. Detalles del original que faltan

- Sprites (`.spr`): miras, humo, sangre, iconos del HUD. No están en `assets/`.
- Sonidos ambientales por mapa (`ambient_generic` en las entidades).
- Entidades de activación de puertas: los brushes móviles funcionan por
  proximidad, pero no por botones/cadenas `target`; también falta ajustar su
  interacción con la navegación de bots.
- `func_breakable` y cristales.
- Escaleras `func_ladder` parcialmente enlazadas en el grafo; ver §3.
- Niebla y cielo por mapa (`light_environment` se lee, pero de forma básica).
- Bots de radio y mensajes de texto del HUD.

## Lo que sí está terminado y verificado

- Lectura de los 15 lumps del `.bsp` en los 10 mapas, sin errores.
- Lectura de mallas, huesos y texturas en los 96 modelos, sin errores.
- Animación de esqueleto (RLE + slerp + skinning GPU) y 215 secuencias
  comprobadas con movimiento real.
- Render de validación (planos de mapas y vistas de modelos) en `docs/previews/`.
- Comprobación de la API de Godot 4.4 en los 19 scripts, incluidas las llamadas
  y señales entre clases del propio proyecto (`tools/gdscript_check.py`).
- Constantes, precios y aritmética del modo de juego contrastados con el 1.5 y
  economía simulada en 200 rondas (`tools/partida_validate.py`).
- Grafo de navegación construido en los 10 mapas: entre 3 793 y 9 853 nodos,
  todos los objetivos de bomba, compra y rehenes alcanzables; 20 subidas por
  `func_ladder` probadas en ambos sentidos y 0-0,3 % de atajos en las aristas
  caminables (`tools/nav_validate.py`).
- Puntería de los bots medida por simulación: aciertos por segundo y tiempo para
  matar a 5, 10, 20 y 30 m (`tools/bots_validate.py`).
