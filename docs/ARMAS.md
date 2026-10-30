# Arsenal

Valores reales tomados de `src/autoload/content.gd`. `Daño` es por bala (sin multiplicadores); `Pen.` es la penetración de paredes; `Prec.` es la dispersión base en grados (menor = mejor).

## Pistolas

| Arma | Precio | Daño | Cadencia | Cargador | Pen. | Prec. | Notas |
|---|---:|---:|---:|---:|---:|---:|---|
| Glock 18 | 400 | 25 | 400 | 20 | 1 | 0.55 | Ráfaga de 3, T |
| USP .45 | 500 | 34 | 400 | 12 | 1 | 0.42 | Silenciable, CT |
| P228 | 600 | 32 | 400 | 13 | 1 | 0.40 | Equilibrada |
| Desert Eagle | 650 | 54 | 267 | 7 | 2 | 0.50 | Headshot casi seguro |
| Five-SeveN | 750 | 25 | 400 | 20 | 2 | 0.36 | Perfora chalecos, CT |
| Dual Berettas | 800 | 36 | 600 | 30 | 1 | 0.75 | Automáticas, T |

## Subfusiles

| Arma | Precio | Daño | Cadencia | Cargador | Precisión |
|---|---:|---:|---:|---:|---:|
| TMP | 1250 | 20 | 857 | 30 | 0.55 (silenciado) |
| MAC-10 | 1400 | 29 | 800 | 30 | 0.80 |
| MP5 Navy | 1500 | 27 | 750 | 30 | 0.45 |
| UMP 45 | 1700 | 34 | 600 | 25 | 0.50 |
| P90 | 2350 | 21 | 857 | 50 | 0.55 |

## Escopetas

| Arma | Precio | Daño | Peregrinos | Cadencia | Cargador |
|---|---:|---:|---:|---:|---:|
| M3 Super 90 | 1700 | 9 | 9 | 80 | 8 (recarga bala a bala) |
| XM1014 | 3000 | 8 | 8 | 171 | 7 (automática) |

## Fusiles

| Arma | Precio | Daño | Cadencia | Cargador | Pen. | Notas |
|---|---:|---:|---:|---:|---:|---|
| FAMAS | 2250 | 30 | 900 | 25 | 2 | Ráfaga de 3, CT |
| Galil AR | 2000 | 30 | 666 | 35 | 2 | T |
| AK-47 | 2500 | 36 | 600 | 30 | 3 | T, one-tap a la cabeza |
| M4A1 | 3100 | 33 | 666 | 30 | 2 | Silenciable, CT |
| SG 552 | 3500 | 33 | 727 | 30 | 2 | Mira 2x, T |
| Steyr AUG | 3500 | 32 | 727 | 30 | 2 | Mira 1.8x, CT |

## Francotiradores

| Arma | Precio | Daño | Cadencia | Cargador | Zoom |
|---|---:|---:|---:|---:|---:|
| Scout | 2750 | 75 | 100 | 10 | 4x |
| AWP | 4750 | 115 | 41 | 10 | 5x |
| G3SG1 | 5000 | 80 | 240 | 20 | 3.5x |
| SG 550 | 4200 | 70 | 240 | 20 | 3.5x |

## Ametralladora

| Arma | Precio | Daño | Cadencia | Cargador | Notas |
|---|---:|---:|---:|---:|---|
| M249 Para | 5750 | 35 | 600 | 100 | 200 de reserva, lenta al caminar |

## Cuerpo a cuerpo y explosivos

| Objeto | Precio | Efecto |
|---|---:|---|
| Cuchillo | — | 40 de daño (90 por la espalda), silencioso |
| Granada HE | 300 | 98 de daño en 7,5 m |
| Flashbang | 200 | Ceguera hasta 4,2 s según ángulo/distancia |
| Granada de humo | 300 | Nube de 4,5 m durante 14 s que corta la visión de los bots |
| C4 | — | 40 s de mecha, 400 de daño en 26 m |

## Equipamiento

| Objeto | Precio | Efecto |
|---|---:|---|
| Chaleco Kevlar | 650 | 100 de armadura (absorbe parte del daño) |
| Casco | 350 | Reduce el daño de cabeza con armadura |
| Kit de desactivación | 200 | Desactiva el C4 en 5 s en vez de 10 s |

## Multiplicadores

- Cabeza ×4 (×0,55 adicional con casco), piernas ×0,75.
- Caída de daño por distancia según `falloff` y `min_mult`.
- Chaleco: reduce según `armor_pen` del arma.
- Velocidad al caminar con cada arma (`speed_mult`, 0,86–1,12).
