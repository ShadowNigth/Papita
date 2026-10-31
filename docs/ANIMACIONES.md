# Animaciones

Cómo se animan los modelos `.mdl` de Counter-Strike 1.5, con el formato y el
algoritmo del motor explicados campo a campo. Todo está implementado dos veces
con la misma lógica: en `scripts/mdl_reader.gd` (el juego) y en
`tools/cs15_validate.py` (la verificación, que además dibuja los fotogramas).

## 1. Dónde está la animación en el fichero

```
studiohdr
 ├─ huesos      (mstudiobone_t, 112 B cada uno)
 ├─ secuencias  (mstudioseqdesc_t, 176 B cada una)
 ├─ texturas
 └─ bodyparts → modelos → mallas → comandos de triángulos
```

Una secuencia no guarda fotogramas completos: guarda **canales comprimidos por
hueso**. El motor los decodifica en cada cuadro. Por eso 95 secuencias de un
soldado caben en 2 MB.

## 2. `mstudioseqdesc_t` (176 bytes)

```
0    char[32] label          // "walk", "run", "death1"...
32   float    fps            // 30 en casi todas
36   int32    flags
40   int32    activity
44   int32    actweight
48   int32    numevents
52   int32    eventindex
56   int32    numframes       // cuadros de la secuencia
60   int32    weightlistindex
64   int32    iklockindex
68   int32    motiontype
72   int32    motionbone
76   vec3     linearmovement
88   int32    autolayerindex
...
120  int32    numblends
124  int32    animindex        // offset ABSOLUTO a los mstudioanim_t
...
172  int32    animdescindex
```

⚠ `numframes` está en **56**, no en 36 (que es donde uno lo buscaría después de
`fps`). Y `animindex` está en **124**, no en 128. Esos 4 bytes de diferencia
hacen que se lea basura en todos los modelos, porque el campo siguiente
(`blendtype[2]`) se interpreta como offset enorme.

## 3. `mstudioanim_t` (12 bytes)

```
uint16 offset[6]
```

Un array de estos, **uno por hueso**, empezando en `animindex`. Los 6 canales
son, en orden: `X, Y, Z` de posición y `X, Y, Z` de rotación.

`offset[c] == 0` significa "canal constante": el valor es el de reposo del hueso
(`mstudiobone_t.value[c]`), sin datos. Casi la mitad de los canales de un modelo
están así.

## 4. `mstudioanimvalue_t` (RLE)

```
byte num.valid    // cuantos valores reales sigue el bloque
byte num.total    // cuantos cuadros cubre el bloque
int16 value[]     // `valid` valores
```

Los valores son **enteros comprimidos**: para obtener el valor real hay que
aplicar `value_reposo + crudo * scale`, donde `scale` es el campo
`mstudiobone_t.scale[c]` (típicamente 1/256). Esto es lo que permite guardar
posiciones en pasos de 1/256 de unidad y rotaciones en pasos de ~0,22 grados.

### Recorrido (port literal de `R_StudioCalcBones`)

```
j = cuadro_buscado
if total < valid: j = 0
while total <= j:
    j -= total
    bloque += (valid + 1) * 2   // +1 por la cabecera de 2 bytes
    if total < valid: j = 0
```

Terminado el bucle hay que decidir de dónde salen los **dos** valores a
interpolar. Esto es la parte sutil, y es literal del motor:

```
if valid > j:
    v1 = valores[j + 1]
    v2 = valores[j + 2]      si valid > j + 1
         v1                  si no, pero total > j + 1
         siguiente_bloque    si no
else:
    v1 = valores[valid]
    v2 = v1                  si total > j + 1
         siguiente_bloque    si no
```

⚠ Si esto se simplifica "a lo bruto" (por ejemplo, interpolando siempre entre
`valores[j]` y `valores[j+1]`), las animaciones se ven **casi** bien pero con
tirones raros: el error aparece solo cuando un bloque cubre varios cuadros.

## 5. De valores a matrices

1. **Posición**: interpolar lineal entre `v1` y `v2` con la fracción de cuadro
   `s`.
2. **Rotación**: convertir cada tripleta a cuaternión y hacer *slerp*. La
   conversión es `AngleQuaternion(..., studio=true)`, que espera los ángulos
   **en radianes** y en orden `pitch, yaw, roll`. El modo Studio asigna:

```
sr,cr = sin/cos(pitch * 0.5)
sp,cp = sin/cos(yaw   * 0.5)
sy,cy = sin/cos(roll  * 0.5)
q.x = sr*cp*cy - cr*sp*sy
q.y = cr*sp*cy + sr*cp*sy
q.z = cr*cp*sy - sr*sp*cy
q.w = cr*cp*cy + sr*sp*sy
```

No reordenar los ángulos antes de esta fórmula: así se conserva exactamente
la orientación de los huesos de StudioModel.

3. **Matriz local** del hueso: `Transform3D(Basis(q), posicion)`.
4. **Matriz global**: multiplicar por la del padre, en orden de jerarquía. En
   Godot no hace falta hacerlo a mano: se llama a `Skeleton3D.set_bone_pose()`
   con la matriz **local** y el esqueleto compone.

## 6. Skinning

El original usa **un hueso por vértice** (`vertinfoindex` es un byte por
vértice). Entonces:

1. Se crea un `Skeleton3D` con los 53 huesos y su `bone_rest` (pose de reposo).
2. La malla se construye con los vértices **ya transformados a la pose de
   reposo** y con `bones = [hueso, 0, 0, 0]`, `weights = [1, 0, 0, 0]`.
3. `Skeleton3D.create_skin_from_rest_transforms()` genera el `Skin` que ata
   malla y esqueleto.
4. En cada `_process`, se calcula la pose con `MdlReader.pose()` y se aplica con
   `set_bone_pose(i, ...)`. El GPU Shader hace el resto.

Por qué así y no reconstruyendo la malla: subir 800 vértices a la GPU 60 veces
por segundo es tirar memoria y ancho de banda; mover 53 matrices es gratis.

## 7. Las secuencias de CS 1.5

Un soldado (`gign`, `terror`, ...) trae 95 secuencias. Las útiles:

| Grupo | Nombres | Cuadros | fps |
|---|---|---|---|
| Reposo | `idle1`, `crouch_idle` | 61 / 31 | 15 / 10 |
| Movimiento | `walk`, `run`, `crouchrun`, `jump` | 33 / 37 / 31 / 61 | 30 / 60 / 30 / 30 |
| Muerte | `death1`, `death2`, `death3`, `crouch_die` | 36 / 41 / 106 / 31 | 30 |
| Disparo | `ref_shoot_ak47`, `ref_shoot_mp5`, ... | 5-6 | 15-20 |
| Apuntado | `ref_aim_*` | 2 (fijos) | 30 |
| Recarga | `ref_reload_*` | 46-91 | 30 |

Las de `aim` tienen 1-2 cuadros **iguales** a propósito: el motor las usa como
pose base para mezclar con los disparos, no como animación en bucle. En la
validación salen como "sin movimiento" y es correcto.

## 8. Verificación

```bash
python3 tools/cs15_validate.py --anim gign:walk --anim terror:run
```

Genera `docs/previews/anim_<modelo>_<secuencia>.png` (tira de 8 fotogramas) y
`.gif` (bucle completo). Además, el validador evalúa 4 cuadros de cada secuencia
en los 96 modelos y comprueba que las poses sean finitas y que el esqueleto se
mueva de verdad:

```
animaciones: 215/261 secuencias evaluadas se mueven (0 problemas)
```

Ese 215/261 es la prueba de que el decodificador RLE funciona: 46 son poses
fijas o modelos de arma, no fallos.
