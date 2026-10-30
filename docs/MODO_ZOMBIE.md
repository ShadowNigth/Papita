# Modo Zombie

Sobrevive a oleadas infinitas con 3 aliados bot. Todo el progreso se guarda (récord de oleada).

## Flujo

1. **Preparación** (18 s): compra con puntos en máquinas de perks, caja misteriosa y munición.
2. **Oleada**: los zombies aparecen en los puntos del mapa (nunca a menos de 10 m del jugador), con intervalo decreciente y máximo de vivos creciente.
3. **Interludio** (9 s): bonus de puntos, curación de 35 y reabastecimiento parcial de todos los supervivientes.
4. Game over si el jugador muere sin Quick Revive.

## Tipos de zombie

| Tipo | Vida | Velocidad | Daño | Puntos | Notas |
|---|---:|---:|---:|---:|---|
| Caminante | 110 | 2.1 | 18 | 60 | Base |
| Corredor | 75 | 4.6 | 14 | 90 | Rápido y frágil (desde oleada 2) |
| Bruto | 480 | 1.7 | 42 | 220 | 25 % de armadura (desde oleada 3) |
| Escupidor | 140 | 2.6 | 12 | 150 | Ataque a distancia (desde oleada 4) |
| Devorador | 2800 | 2.2 | 65 | 1200 | Jefe cada 5 oleadas |

Escalado por oleada: vida ×(1 + 0,13·(n−1)), velocidad ×(1 + 0,018·(n−1)) hasta +40 %, probabilidad de especiales hasta 55 %, jefe cada 5.

## Puntos

- 10 por impacto (20 con Double Tap).
- Puntos del tipo de zombie + bonus por la baja.
- Bonus de fin de oleada: 150 + 60·oleada.

## Perks

| Perk | Precio | Efecto |
|---|---:|---|
| Juggernog | 2500 | Vida máxima 200 y regeneración lenta |
| Speed Cola | 2000 | Recarga y desenfunde 45 % más rápidos |
| Double Tap | 2000 | Doble de puntos y 15 % más cadencia |
| Quick Revive | 2500 | Revives una vez con 50 de vida |
| Mule Kick | 4000 | Munición de reserva infinita |

## Caja misteriosa y munición

- Caja: 950 puntos → un arma aleatoria entre 15 del juego con munición completa.
- Crate de munición: 450 puntos → cargador lleno y reserva máxima para todas las armas.

## Consejos

- Las máquinas de perks brillan; los nombres flotan sobre ellas.
- Los escupidores disparan proyectiles verdes: rompe la línea de visión.
- Las barricadas del mapa sirven para embudar a la horda.
