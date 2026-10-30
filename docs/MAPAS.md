# Mapas

Todos los layouts son **originales**, inspirados en la topología de los clásicos. Se definen en `src/world/maps.gd` con un DSL de bloques (`_solid`, `_wall_x`, `_wall_z`, `_room`, `_stairs`, `_platform`) y props.

| ID | Nombre | Modo | Tema | Ambiente | Rasgos |
|---|---|---|---|---|---|
| `de_dust2` | Dust II | Bombeo | Desierto | Día | Sitio A elevado con rampa, túnel B, medio con puertas dobles, patio de spawn |
| `de_inferno` | Inferno | Bombeo | Mediterráneo | Atardecer | Callejones, plaza con fuente, balcón sobre A, puestos de mercado |
| `de_aztec` | Aztec | Bombeo | Selva | Atardecer | Río central con puente, templo A elevado, sitio B, vegetación densa |
| `de_nuke` | Nuke | Bombeo | Industrial | Nublado | Nave con plataforma A elevada, sala B, containers y camión |
| `de_train` | Train | Bombeo | Patio ferroviario | Nublado | Vagones como cobertura, depósito cubierto, nieve y farolas |
| `cs_office` | Office | Rehenes | Oficina | Nublado | Edificio con oficinas, escritorios, pasillos y patio de camiones |
| `cs_italy` | Italy | Rehenes | Pueblo italiano | Día | Plaza con fuente, casas, mercado y callejones |
| `de_dust` | Dust | Bombeo | Desierto | Día | El original: dos sitios y un túnel central |
| `zm_mansion` | Mansion | Zombie | Mansión | Noche | Salón, altillo con escalera, 6 spawns de horda, 4 máquinas de perks |
| `zm_dust_night` | Dust Night | Zombie | Desierto nocturno | Noche | Dust de noche con barricadas, 5 perks, caja y munición |

## Detalles de construcción

- **`_room`**: crea piso, cuatro paredes con huecos para puertas/ventanas y techo; añade una luz interior.
- **`_wall_openings`**: divide un muro en segmentos alrededor de los huecos (dinteles y alféizares incluidos).
- **NavGraph**: la navegación se hornea con rayos que ignoran techos por encima de 2,9 m, de modo que los interiores son transitables.
- **Props**: cajas, barriles, sacos de arena, autos, camiones, árboles, palmeras, farolas, lámparas colgantes, mesas, sillas, gabinetes, escritorios, computadoras, containers, vagones, escombros, pallets, puestos de mercado, fuentes y barricadas.

## Añadir un mapa nuevo

1. Añade una entrada en `Content.MAPS` (id, nombre, modo, tema, ambiente, descripción).
2. Crea la función `_mi_mapa()` en `src/world/maps.gd` y regístrala en `Maps.build()`.
3. Define `spawns_ct`, `spawns_t`, `sites`/`hostages`/`rescue` o `zombie_spawns`, `perks` y `mystery`.
4. El tema debe existir en `MaterialLib.PALETTES` (o reutiliza uno).
