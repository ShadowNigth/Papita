# Arquitectura técnica

## Ciclo de vida

`main.tscn` → `src/core/app.gd` (nodo raíz `App`) → alterna entre `Menu` y `MatchGame`.

Autoloads (en orden):

1. **Settings** — carga `user://settings.cfg`, aplica vídeo/audio/controles, guarda perfil y progreso.
2. **I18n** — tablas ES/EN y `t()`.
3. **AudioBank** — sintetiza el audio (en hilo aparte) y expone `play_ui`, `play_2d`, `play_at`, `weapon_fire`, `footstep`, `set_music`, `set_ambience`.
4. **Content** — base de datos pura: `WEAPONS`, `EQUIPMENT`, `BUY_MENU`, `MAPS`, `ZOMBIE_TYPES`, `PERKS`, `DIFFICULTY`, economía y escalado de oleadas.

## Flujo de una partida

```
App.start_match(map, mode, team, bots, diff)
  └─ MatchGame.start_match()
       ├─ Maps.build(map_id)              → layout (bloques, props, luces, spawns, sitios)
       ├─ MapBuilder.setup(layout)        → geometría + ambiente + props + partículas
       ├─ MapBuilder.bake_navigation()    → NavGraph (grilla de alturas + A*)
       ├─ Player / Bot(s) / Hostage(s)
       ├─ HUD + InGameUI
       └─ start_round()                   → congelado, compra, objetivos, ronda en vivo
```

### Rondas (bomb / hostage)

- `freeze` (4 s): compra libre, movimiento bloqueado.
- `live`: ronda activa, reloj, objetivos, comprobación de fin.
- `end` (4,5 s): recompensas y siguiente ronda.
- Fin de partida a 16 rondas.

Economía: `START_MONEY` 800, victoria 3250 (3500 por bomba), bonus por derrota 1400→3400 según racha, plantado 800, desactivación 800, rescate 1000, teamkill −3300, tope 16000.

### Combate

`Combatant._do_fire()` → `_hitscan()` → `PhysicsRayQueryParameters3D` con máscara `1 | PLAYER_LAYER`:

1. Si acierta un `Combatant`, calcula hitbox (`head/chest/legs`), daño (base × caída por distancia × zona × chaleco) y aplica `take_damage`.
2. Si acierta geometría, genera impacto y, si el arma penetra, busca la salida y continúa el rayo (hasta 3 segmentos).
3. Efectos: trazadora, chispas, polvo, sangre, sonido posicional.

Movimiento: aceleración/fricción en suelo, aire con control limitado, salto, crouch (cápsula reducida), paso automático en escalones y sonido de pasos según velocidad.

### IA

`Bot._think()` cada 160 ms:

- `_find_visible_enemy()`: FOV + raycast + humo.
- Estados: `engage`, `search`, `investigate`, `attack`, `plant`, `defuse`, `defend`, `rescue`, `roam`.
- `_combat_movement()`: ruta A* (`NavGraph.find_path`), strafing, separación, salto de obstáculos, desatasco.
- Disparo con reacción, error de puntería, ráfagas y pausas; no dispara si un aliado está en la línea.

Zombies: apuntan al superviviente más cercano, atacan cuerpo a cuerpo o escupen a distancia, con escalado de vida/velocidad por oleada.

### Navegación

`NavGraph`: celdas de 0,8 m, altura y bloqueo obtenidos con rayos (ignorando techos > 2,9 m) + consulta de forma (cápsula 0,62 × 1,7). A* con heap binario, costo extra por desnivel y suavizado por línea de visión.

### Materiales

`MaterialLib.surface(kind, theme, variant)` genera:

- **Albedo** 128×128 según patrón (ladrillo, madera, metal, arena, musgo…), ruido FastNoiseLite (fractal y celular), grano y variación de color.
- **Normal** por derivadas del mapa de altura.
- **ORM** (AO/rugosidad/metálico).

Se cachea por `kind|theme|variant|wetness`. El shader `surface.gdshader` muestrea en triplanar y añade desgaste, humedad y musgo.

### Audio

`Synth` construye buffers `PackedFloat32Array`:

- Ruido filtrado paso bajo con envolventes exponenciales (cuerpo de disparo, pasos, explosiones).
- Tonos con barrido de frecuencia (seno, sierra, cuadrada, triangular).
- Reverb de peine, saturación `tanh`, normalización y conversión a `AudioStreamWAV` 16 bits mono 22 050 Hz.

`AudioBank` construye el banco esencial en un `Thread`, mezcla los resultados en `_process` y sintetiza música/ambientes en segundo plano.

## Rendimiento

- Materiales y mallas de props compartidos por caché.
- Luces con sombra limitadas; farolas y props sin sombra.
- Partículas con `visibility_aabb` acotado y autodestrucción.
- HUD dibujado con `_draw` (sin árbol de nodos por elemento).
- Audio 3D limitado a 48 reproductores simultáneos.

## Guardado

`user://settings.cfg` (ConfigFile) con secciones `video`, `audio`, `gameplay`, `controls`, `profile`, `progress`. Se guarda con debounce (0,8 s) y al cerrar.
