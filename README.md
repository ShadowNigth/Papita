# PAPITA · COUNTER-STRIKE 1.5 REFORGED

Recreación jugable y **completa** del clásico *Counter-Strike 1.5*, hecha desde cero en **Godot 4.4** como proyecto personal (sin distribución pública).

> **No es un volcado de archivos de Valve.** Todo el código, los modelos 3D, las texturas PBR y los sonidos son originales y se generan de forma procedural dentro del juego. El proyecto reproduce fielmente las mecánicas, la economía, las armas y los mapas clásicos, pero con arte propio: no se incluye ni un solo asset original de Counter-Strike.

---

## 1. Qué incluye

### Armas (24 de fuego + cuchillo + granadas + C4 = 29 objetos)
- **Pistolas:** Glock 18 (ráfaga de 3), USP .45 (silenciable), P228, Desert Eagle, Five-SeveN, Dual Berettas.
- **Subfusiles:** TMP (silenciado), MAC-10, MP5 Navy, UMP 45, P90.
- **Escopetas:** M3 Super 90 (corredera), XM1014.
- **Fusiles:** FAMAS (ráfaga), Galil, AK-47, M4A1 (silenciable), SG 552 (mira 2x), Steyr AUG (mira 1.8x).
- **Francotiradores:** Scout, AWP, G3SG1, SG 550.
- **Ametralladora:** M249 Para.
- **Extras:** cuchillo (apuñalamiento por la espalda), HE, flashbang, granada de humo y C4.
- Balística con dispersión por movimiento/aire/agachado, retroceso ascendente, penetración de paredes, daño por zona (cabeza ×4, piernas ×0.75), caída de daño por distancia, chaleco y casco, headshots, hitmarkers y killfeed.

### Modos de juego
- **Bombeo (`de_`)**: compra, economía por rondas (victoria, bonus por racha de derrotas, recompensas por plantar/desactivar), plantado de C4 con cuenta atrás de 40 s, desactivación con/sin kit, explosión con daño en área.
- **Rehenes (`cs_`)**: liberación, escolta y rescate de rehenes.
- **Zombie (`zm_`)**: oleadas infinitas con 5 tipos de no-muertos (caminante, corredor, bruto, escupidor y jefe), puntos por daño/baja, caja misteriosa, máquinas de perks (Juggernog, Speed Cola, Double Tap, Quick Revive, Mule Kick), reabastecimiento de munición, aliados bot y progresión de dificultad.

### Mapas (10)
`de_dust2`, `de_inferno`, `de_aztec`, `de_nuke`, `de_train`, `cs_office`, `cs_italy`, `de_dust`, `zm_mansion`, `zm_dust_night`.

Cada mapa se reconstruye proceduralmente: geometría, props, luces, cielo, niebla, agua, partículas ambientales y **malla de navegación horneada** para los bots.

### Bots
- 42 nombres, 5 niveles de dificultad (reacción, error de puntería, FOV, oído, vida).
- Percepción por línea de visión y sonido, combate con ráfagas, strafing, recarga, uso de granadas al comprar, objetivos (plantar, desactivar, rescatar, defender), separación entre bots y desatasco.
- Navegación A* sobre grilla de altura con escaleras/rampas, suavizado de ruta y saltos.

### Menús y configuración
- Menú principal con escenario 3D animado, selección de modo, mapa y bando.
- **Arsenal** con vista previa 3D y estadísticas reales de cada arma.
- **Estadísticas** de perfil, rangos y 10 logros persistentes.
- **Opciones completas**: vídeo (modo de pantalla, resolución, FOV, MSAA, sombras, SSAO, SSIL, bloom, niebla volumétrica, VSync, brillo), audio (master/SFX/música/UI/voces/mute), juego (sensibilidad, invertir Y, bots, dificultad, duración de ronda, tiempo de compra, fuego amigo, sangre, HUD, mira, idioma) y **controles con reasignación de teclas**.
- Menú de pausa, tienda de compra con categorías, marcador (TAB), consola de comandos, ayuda (F1) y pantallas de fin de partida / game over.
- Guardado de ajustes y progreso en `user://settings.cfg`.

### Iluminación "realista" (shaders)
- `shaders/surface.gdshader`: material PBR triplanar con albedo + normal map + ORM procedurales, desgaste, humedad a ras de suelo, musgo y rim light.
- `shaders/sky.gdshader`: cielo atmosférico con sol/luna, halo, nubes noise y estrellas.
- `shaders/water.gdshader`: agua con oleaje, normales animadas y transparencia.
- `shaders/scope.gdshader`: mira telescópica con retícula y viñeta.
- `shaders/foliage.gdshader`: vegetación con viento.
- Post-proceso del `WorldEnvironment`: ACES, SSAO, SSIL, SSR, niebla volumétrica, bloom, MSAA y sombras PSSM 4-splits.
- Viewmodel en capa propia con `no_depth_test` y linterna con sombras.

### Audio 100 % procedural
Todos los sonidos se sintetizan por DSP al arrancar: 16 familias de disparos con variantes, recargas, corredera, cuchillo, impactos, rebotes, pasos, salto, explosiones, flashbang, humo, C4, gritos, gruñidos de zombie, perks, interfaz, ambientes y dos temas musicales. Se construye en un hilo aparte para no congelar el menú.

---

## 2. Cómo ejecutarlo

### Requisitos
- **Godot 4.4** (estable) — versión estándar, no hace falta C#.
- Windows / Linux / macOS con GPU que soporte Forward+ (Vulkan 1.0+).

### Pasos
1. Abre Godot 4.4 → **Import** → selecciona `project.godot`.
2. Espera el primer import (Godot registra los `class_name` y recursos).
3. Pulsa **F5** (o el botón de play). La escena principal es `main.tscn`.
4. En el menú: `JUGAR` → modo → mapa → bando. Para zombies: `MODO ZOMBIE` → mapa.

### Exportar un ejecutable (opcional, uso personal)
1. Instala las *Export Templates* de Godot 4.4 (`Editor → Manage Export Templates`).
2. `Project → Export → Add → Windows/Linux/macOS`.
3. Activa *Embed PCK* si quieres un único archivo. Exporta.
> No distribuyas el binario: es un proyecto privado de homenaje.

---

## 3. Controles por defecto

| Acción | Tecla |
|---|---|
| Moverse | `W A S D` |
| Saltar / agacharse | `Espacio` / `Ctrl` |
| Caminar silencioso | `Shift` |
| Disparar / mira y silenciador | Clic izquierdo / clic derecho |
| Cambiar arma | Rueda del ratón, `1-5`, `Q` |
| Recargar | `R` |
| Comprar | `B` |
| Usar / plantar / desactivar | `E` (mantener) |
| Soltar arma | `G` |
| Linterna | `F` |
| Inspeccionar arma | `I` |
| Marcador | `Tab` (mantener) |
| Pausa | `Esc` |
| Consola | `` ` `` |
| Ayuda | `F1` |

Todo es reasignable en **Opciones → Controles**.

---

## 4. Estructura del proyecto

```
project.godot              Configuración, autoloads y render
main.tscn / src/core/app.gd  Raíz: alterna menú y partida
icon.svg                   Icono

src/autoload/
  settings.gd               Ajustes persistentes, perfil, progreso, calidad
  i18n.gd                   Traducciones español/inglés
  audio_bank.gd             Cache y reproducción de audio sintetizado
  content.gd                Base de datos: armas, economía, mapas, zombies, perks

src/core/
  input_setup.gd            Acciones y reasignación de teclas
  synth.gd                  Sintetizador DSP de todos los sonidos

src/world/
  maps.gd                   Layouts de los 10 mapas (DSL de bloques y props)
  map_builder.gd            Geometría, ambiente, luces, props, navegación
  nav_graph.gd              Grilla de alturas + A* con suavizado
  material_lib.gd           Texturas PBR procedurales y materiales
  prop_lib.gd               Props 3D (cajas, autos, trenes, árboles, etc.)

src/entities/
  combatant.gd              Movimiento CS, armas, balística, daño, muerte
  player.gd                 Primera persona, cámara, viewmodel, entrada
  bot.gd                    IA de bots y de zombies
  actor_model.gd            Modelo 3D animado de soldado/zombi
  viewmodel.gd              Arma en primera persona (sway, recoil, ADS)
  weapon_model.gd           Constructor 3D de las 29 armas y objetos
  projectile.gd             Granada física (HE/flash/humo)
  bomb.gd                   C4 con cuenta atrás y desactivación
  pickup.gd                 Armas en el suelo
  hostage.gd                Rehenes que siguen al CT

src/game/match.gd           Director de partida: rondas, economía, objetivos, oleadas
src/fx/fx.gd                Trazadoras, impactos, sangre, explosiones, humo

src/ui/
  menu.gd                   Menú principal + flujo + arsenal + estadísticas
  hud.gd                    HUD en juego (mira, vida, radar, killfeed, scope)
  ingame_ui.gd              Tienda, pausa, marcador, consola, ayuda, fin de ronda
  options_panel.gd          Panel de opciones reutilizable
  ui_theme.gd               Tema visual unificado

shaders/                    surface, sky, water, foliage, scope
assets/fonts/               DejaVu (licencia incluida)
docs/                       Documentación extendida
```

Más detalle en [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md), [`docs/ARMAS.md`](docs/ARMAS.md), [`docs/MAPAS.md`](docs/MAPAS.md), [`docs/MODO_ZOMBIE.md`](docs/MODO_ZOMBIE.md) y [`docs/AVISO_LEGAL.md`](docs/AVISO_LEGAL.md).

---

## 5. Consola de comandos

`` ` `` abre la consola. Comandos: `help`, `give <arma>`, `money <n>`, `god`, `noclip`, `kill`, `heal`, `wave <n>`, `nextwave`, `map <id>`, `difficulty <0-4>`, `time <seg>`, `clear`, `quit`.

---

## 6. Decisiones técnicas

- **Sin assets externos**: todo el contenido se genera en runtime. El repositorio pesa poco y no hay problemas de licencias.
- **Texturas PBR**: ruido celular/Worley + grano + normal por derivadas de altura + ORM, con triplanar en world space para que no se estiren las paredes.
- **Navegación**: en vez de hornear NavMesh (lento y frágil con geometría procedural), se muestrea el mundo con rayos y se construye una grilla de alturas con A* y suavizado por línea de visión.
- **Audio**: síntesis DSP (ruido filtrado, senos/sierras con envolventes, reverb de peine, saturación) y construcción en un `Thread` para evitar tirones.
- **Rendimiento**: límite de luces con sombras, partículas acotadas, materiales cacheados por tipo/variante y actualización de HUD por dibujo inmediato (`_draw`).

## 7. Estado y limitaciones conocidas

- **Aún no se ha ejecutado dentro del motor**: el proyecto se escribió y se validó de forma estática (parser de GDScript, formato, comprobaciones de API) en un entorno sin Godot instalado. La primera vez que lo abras pueden aparecer avisos menores; están anotados abajo.
- El arte es una interpretación estilizada (low-poly procedural), no modelos fotorrealistas.
- Los bots juegan los objetivos y combaten, pero no ejecutan estrategias de equipo avanzadas ni *smoke lineups*.
- Sin multijugador en red: es un proyecto para jugar solo contra bots (tal como se pidió).
- El modo espectador es básico: al morir se observa desde el cadáver hasta la siguiente ronda.
- La primera carga del mapa genera texturas y navegación; puede tardar unos segundos según la CPU.

## 8. Aviso legal

Counter-Strike y sus marcas pertenecen a Valve Corporation. Este es un proyecto **privado, no comercial y no distribuido**, hecho como homenaje y ejercicio técnico. No contiene código, mapas, modelos, texturas ni sonidos originales de Valve.
