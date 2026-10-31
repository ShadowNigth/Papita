# Arquitectura

## Idea

Un solo motor, Godot 4.4, y **los assets originales de Counter-Strike 1.5**. El
trabajo de verdad está en los dos lectores de formato: el resto es un juego
normal de Godot construido encima.

```
assets/maps/cs15/*.bsp ──► bsp_reader.gd ──► map_builder.gd ──► malla + colisión + luz
assets/models/cs15/*.mdl ─► mdl_reader.gd ──► ArrayMesh (bind pose)
assets/sounds/cs15/*.wav ─► audio.gd ───────► AudioStreamWAV
assets/valve/gfx/palette.lmp ─► palette.gd ─► Color[] para los índices de 8 bits
```

## Por qué no se usan importadores

Godot no sabe leer `.bsp` ni `.mdl`, y no hay importadores mantenidos para
Godot 4. Escribirlos es la parte interesante del proyecto y, además, la única
forma de que los assets no se conviertan en una copia muerta: aquí se leen tal
cual, en tiempo de ejecución, sin pasos previos ni ficheros intermedios.

Ventaja práctica: si cambias un `.bsp` o un `.mdl`, el juego lo refleja al
arrancar. Nada que reimportar.

## Flujo de arranque

1. `game.gd::_ready()` lee `--map` de la línea de comandos.
2. Carga la paleta (`palette.gd`): `palette.lmp` si existe, si no una generada.
3. `BspReader.cargar()` parsea el `.bsp` completo.
4. `MapBuilder.construir()`:
   - Empaqueta los lightmaps en un atlas y guarda el hueco de cada cara.
   - Triangula las caras en abanicos, agrupadas por textura.
   - Crea una superficie por material con UV (`UV`) y UV de luz (`UV2`).
   - Genera la colisión concava.
   - Añade `WorldEnvironment` y una `DirectionalLight3D` (esta última solo
     afecta a los modelos: la geometría es `unshaded` y usa el lightmap).
5. Coloca al jugador en un spawn leído del lump de entidades.
6. Crea el HUD y captura el ratón.
7. `_crear_director()` arranca la partida: `MatchDirector` recibe el jugador,
   los actores y las zonas de bomba y compra que saca `MapBuilder` del `.bsp`.

## Decisiones

**Geometría `unshaded` + lightmap.** El original no tenía luces dinámicas: toda
la iluminación está horneada en el `.bsp`. Replicarlo da el aspecto correcto y
cuesta cero en rendimiento. El shader hace `pow(color, 2.2)` para pasar de sRGB
a lineal antes de multiplicar por la luz, y el lightmap se multiplica por 2.2
porque los valores de 1999 vienen ya "brillantes".

**Una superficie por textura.** Un mapa tiene ~5000 caras y ~150 texturas; con
una superficie por cara serían 5000 draw calls. Agrupando por textura baja a
~150.

**Atlas de luz único.** Cada cara tiene su propio lightmap con su propio tamaño;
en vez de una textura por cara se empaqueta todo en una imagen y se guarda el
rectángulo de cada cara para calcular la `UV2`.

**Escala 0.025.** GoldSrc usa ~0.025 m por unidad. Se aplica al leer los
vértices, no al escalar el nodo, para que la física de Godot trabaje en metros
(las cápsulas, la gravedad y los rayos de arma esperan eso).

**Constantes del movimiento copiadas del motor.** No están ajustadas "hasta que
se siente bien": son `sv_accelerate`, `sv_friction`, `sv_airaccelerate`,
`sv_stopspeed` y las velocidades de CS 1.5, convertidas a metros. Es lo que hace
que moverse se parezca al original.

## Animación

Los modelos no se reconstruyen por cuadro: `mdl_reader.gd` crea un
`Skeleton3D` con los 53 huesos del `.mdl` y sube la malla una sola vez con
`bones`/`weights` por vértice (un hueso por vértice, como el original). Cada
cuadro, `pose()` decodifica los canales RLE y devuelve una `Transform3D` local
por hueso que se aplica con `set_bone_pose()`; el `Skin` lo resuelve en la GPU.

`actor_model.gd` es el nodo que encadena eso con el estado del juego:
`animar_por_velocidad()` elige entre `idle1`, `walk`, `crouchrun` y `run` según
los metros por segundo, y `morir()` reproduce una de las tres muertes.

## Modo de juego

`match_director.gd` es el único que decide cuándo empieza y acaba una ronda; los
demás nodos no saben en qué estado está la partida, solo reaccionan a sus
señales (`ronda_iniciada`, `ronda_terminada`, `estado_cambiado`, `mensaje`).

```
CONGELACION --(6 s)--> EN_JUEGO --(bomba)--> BOMBA_PLANTADA
     ^                    |                       |
     |                    v                       v
     +--------------- FIN_RONDA  <---------- (explota / se desactiva)
```

- Cada 5 s de `FIN_RONDA` se lanza `_iniciar_ronda()`: resucita al jugador y a
  los actores, y devuelve a cada uno a su punto de aparición. Si murió pierde
  el equipo; si sobrevivió lo conserva, como en el original.
- Las zonas no son inventadas: `func_bomb_target` y `func_buyzone` son brushes.
  `BspReader.caja_entidad()` busca su `model "*N"` y devuelve la caja del brush
  model ya en metros; `posicion_en_zona()` comprueba un punto contra esas cajas.
- `economy.gd` no tiene nodos ni estado: son funciones puras, para poder
  razonarlas aparte. `bomb.gd` concentra toda la cuenta atrás y el daño.
- El HUD **no** consulta al director: `game.gd` copia cada cuadro los valores
  (reloj, marcador, dinero, fase, tiempo de bomba) a campos del HUD. Así el HUD
  sigue pudiendo dibujarse sin partida, por ejemplo en la pantalla de prueba.

## Bots y navegación

Un bot es un `ActorModel` (el `.mdl` animado) más un `BotAI` hijo que lo mueve y
le da vida de combate. El actor no sabe nada de IA y la IA no sabe nada de
esqueletos: uno pone la animación y el otro decide a dónde ir.

El movimiento no usa `NavigationServer3D` ni un NavMesh horneado a mano. Se
construye un grafo propio a partir del `.bsp`, que es lo que hace posible
navegar sin importadores ni pasos previos:

```
lump 1 planos ─┐
lump 5 nodos  ─┼─► contenido(punto)  ──►  ¿es sólido?  ──►  muestreo de caras de suelo
lump 10 hojas ─┘                                              (40 u, cabe el actor)
                                                                     │
                                            A*  ◄── nodos + aristas ──┘
                                             │
                                    suavizado por línea recta
```

**Por qué el árbol BSP y no rayos físicos.** El mapa ya está particionado: un
punto se resuelve bajando por el árbol, sin tocar el motor de física ni depender
de que la malla de colisión esté bien. Es el mismo dato que usaba GoldSrc, así
que la respuesta coincide con la del original en casos raros (esquinas, rampas).

**Por qué no se encoge cada cara.** Primero se probó a encoger cada polígono
para dejar margen a la pared, y salió un grafo con el 4 % de los nodos: el suelo
de un mapa no es una cara, son cientos de trozos cortados por textura y por
hoja, y encoger cada trozo deja los corredores partidos en tiras que no dan ni
un punto. La solución que funciona es muestrear la cara entera y comprobar el
hueco alrededor del punto con el propio árbol.

**Qué se considera "se puede andar".** Caras del modelo 0 cuya normal mira hacia
arriba (coseno ≥ 0,6), sin texturas de cielo, clip ni agua; puntos donde caben
el cuerpo y la cabeza del actor; y aristas entre nodos vecinos con un desnivel
de hasta 40 unidades, que es lo que permite subir las escaleras del original sin
modelarlas.

**Lo que no hay.** Escaleras de mano, saltos y puertas: por eso hay un 15-45 %
de nodos inalcanzables según el mapa (tejados y cornisas), y `PENDIENTE.md` lo
lista como deuda. Si A* no encuentra ruta, el bot va en línea recta: se queda
pegado a la pared, pero no se queda quieto.

## Los tres niveles de verificación

Este proyecto no se pudo ejecutar en el entorno donde se escribió, así que se
verificó en tres capas:

1. **Formato**: `tools/cs15_validate.py` reimplementa los mismos offsets en
   Python y los ejecuta contra los 10 mapas y 96 modelos. Si los números cuadran
   y la geometría se dibuja, los lectores de GDScript están bien.
2. **Sintaxis**: `tools/gdscript_check.py` parsea cada `.gd` con `gdtoolkit`.
3. **API**: el mismo script contrasta cada `Clase.metodo()` y cada constante
   contra `docs/godot44_api.json.gz`, un volcado de la API de Godot 4.4. Esto es
   lo que detectó que `SurfaceTool.get_vertex_count()` no existe.

Lo que ninguna de las tres capas puede comprobar es el comportamiento en
ejecución. Eso queda para la primera vez que abras el editor.
