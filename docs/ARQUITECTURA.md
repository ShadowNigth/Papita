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
