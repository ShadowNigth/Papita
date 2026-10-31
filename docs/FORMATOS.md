# Formatos: `.bsp` v30 y `.mdl` v10 campo a campo

Todo lo que hay aquí está comprobado contra los ficheros reales del repositorio
y contra el código del motor (`Xash3D-FWGS`, en `legacy/xash/`), no contra
documentación de terceros. Los errores que se marcan con ⚠ son los que costaron
depuración de verdad.

## 1. `.bsp` de GoldSrc (versión 30)

### Cabecera

```
offset 0   int32  version          -> 30
offset 4   lump[15] { int32 ofs; int32 len; }
```

⚠ El header son **15 lumps**, no 16. Contar 16 hace que el lump 3 se lea del
sitio equivocado y todo lo demás sale basura (fue el primer error del proyecto
anterior: informaba "0 texturas embebidas" en todos los mapas).

| # | Lump | Contenido |
|---|---|---|
| 0 | entidades | texto `{ "clave" "valor" }` |
| 1 | planos | plano + tipo |
| 2 | texturas | miptex indexadas |
| 3 | vértices | `float32 x, y, z` |
| 4 | visibilidad | PVS comprimido |
| 5 | nodos | BSP de partición |
| 6 | texinfo | proyección de textura por cara |
| 7 | caras | 20 bytes cada una |
| 8 | iluminación | lightmaps RGB |
| 9 | clipnodes | colisión del motor |
| 10 | hojas | |
| 11 | marksurfaces | |
| 12 | aristas | pares de índices de vértice |
| 13 | surfedges | arista con signo |
| 14 | modelos | brush models |

### `mtexinfo_t` (40 bytes)

```
0   float32 vecs[2][4]   // proyección: s = (u·p) + offset
32  int32   miptex       // índice en el lump de texturas
36  int32   flags
```

La coordenada de textura de un vértice es
`s = x*vecs[0][0] + y*vecs[0][1] + z*vecs[0][2] + vecs[0][3]`, y lo mismo para
`t` con `vecs[1]`. La UV final es `s / ancho_textura`.

### `miptex_t` (lump 2)

```
0   char[16] name
16  uint32   width
20  uint32   height
24  uint32   offsets[4]   // 4 mips; offsets[0] == -1 => textura externa (WAD)
40  ...      datos        // mip 0 en offsets[0], 8 bits por pixel
```

⚠ Los mapas de este repositorio **no traen paleta embebida** (el contador tras
el mip 0 no es 256): los píxeles son índices y el color vive en
`palette.lmp`. Sin ese fichero hay que aproximar la paleta.

### `dface_t` (20 bytes)

```
0   int16 plano
2   int16 lado
4   int32 firstedge     // índice en surfedges
8   int16 numedges
10  int16 texinfo
12  uint8 estilos[4]
16  int32 lightofs      // -1 si la cara no tiene luz
```

`surfedges[i]`: valor positivo → arista `(v0, v1)`; negativo → `(v1, v0)`.
Las caras son polígonos **convexos**: se triangulan en abanico.

### Lightmaps

Por cara: se calcula la caja de los vértices en coordenadas de luxel
(`s/16`, `t/16`), redondeando hacia fuera. El tamaño en luxeles es
`(max_s/16 - min_s/16 + 1) × (max_t/16 - min_t/16 + 1)`, y los píxeles son
`ancho * alto * 3` bytes RGB a partir de `lightofs` (relativo al inicio del lump
de luz). La UV de luz de un vértice es su posición en luxeles normalizada a esa
caja.

### Árbol BSP: `dplane_t`, `dnode_t`, `dleaf_t` (lumps 1, 5 y 10)

Es lo que permite preguntar "¿este punto es sólido?" sin tocar el motor de
física, y de ahí sale el grafo de navegación de los bots.

| Estructura | Lump | Tamaño | Campos que se usan |
|---|---|---|---|
| `dplane_t` | 1 | 20 B | normal (3 float), dist (float), tipo (int32) |
| `dnode_t` | 5 | 24 B | planenum (int32), children[2] (int16 ×2), caja, firstface/numfaces |
| `dleaf_t` | 10 | 28 B | contents (int32), visofs, caja, marcas de superficie |

El recorrido es el de Quake: se empieza en el nodo 0 y en cada uno se calcula
`dot(normal, p) - dist`; si es ≥ 0 se baja por `children[0]` y si no por
`children[1]`. Un hijo negativo es una hoja: `contents` vale **-1 vacío**,
**-2 sólido** y **-3 agua**. Lo que queda fuera del mapa es sólido, igual que
en el original.

> Ojo con el lump 14 (`dmodel_t`, 64 B): el rango de caras del **mundo** está
> en los bytes 56 y 60 (`firstface`, `numfaces`), no al principio. Las caras de
> los modelos `*N` vienen después.

## 2. `.mdl` StudioModel (versión 10)

### `studiohdr_t` (los offsets que importan)

```
0    char[4]  ident          -> "IDST"
4    int32    version        -> 10
8    char[64] name
88   vec3     bbmin
100  vec3     bbmax
140  int32    numbones
144  int32    boneindex
164  int32    numseq
168  int32    seqindex
180  int32    numtextures
184  int32    textureindex
192  int32    numskinref
196  int32    numskinfamilies
200  int32    skinindex
204  int32    numbodyparts
208  int32    bodypartindex
```

⚠ Estos offsets no están en el orden "natural": `numbodyparts` va detrás de
`skinindex`, y entre `numbones` y `numseq` hay un hueco de 20 bytes. Leerlos de
memoria (en vez de del `studio.h` del motor) produce valores absurdos como
"129 secuencias" en el modelo del rehén.

### `mstudiobone_t` (112 bytes)

```
0    char[32] name
32   int32    parent      // -1 en la raíz
36   int32    unused
40   int32    bonecontroller[6]
64   float32  value[6]    // [0..2] posición, [3..5] rotación (radianes)
88   float32  scale[6]    // compresión de controladores (1/256)
```

⚠ `scale[]` **no** es una escala de la matriz: es el factor de compresión de los
controladores. Multiplicar la matriz por él colapsa el modelo a un punto (pasó:
el GIGN se dibujaba como un triángulo diminuto).

### `mstudiobodyparts_t` (76 bytes) y `mstudiomodel_t` (112 bytes)

```
bodypart: 0 char[64] name | 64 int32 nummodels | 68 int32 base | 72 int32 modelindex
model:    0 char[64] name | 64 int32 type | 68 float32 radius | 72 int32 nummesh
          76 int32 meshindex | 80 int32 numverts | 84 int32 vertinfoindex
          88 int32 vertindex | 92 int32 numnorms | 96 ...
```

- `vertindex` → `numverts` vértices de 3 `float32` (espacio **local del hueso**).
- `vertinfoindex` → `numverts` **bytes**, uno por vértice: el hueso al que
  pertenece.

### `mstudiomesh_t` (20 bytes)

```
0  int32 numtris
4  int32 triindex    // offset ABSOLUTO desde el inicio del fichero
8  int32 skinref     // índice de textura
```

⚠ `triindex` es absoluto, no relativo a la malla. Sumarle la base de la malla
(el instinto natural) descoloca la lectura.

### Comandos de triángulos

```
short count
  count > 0 : strip de |count| vértices
  count < 0 : fan  de |count| vértices
  count == 0: fin de la lista
```

⚠ Cada vértice son **4 shorts**: `(indice, indice_normal, s, t)`. Leerlos como
un short por vértice hace que todo se desalinee a partir del segundo triángulo
(se ve como triángulos que atraviesan el mapa).

La UV es `s / ancho_textura`, `t / alto_textura`, con la textura `skinref`.

### `mstudiotexture_t` (80 bytes)

```
0   char[64] name
64  int32    flags
68  int32    width
72  int32    height
76  int32    index    // offset ABSOLUTO de los píxeles (8 bits por píxel)
```

Al contrario que en el `.bsp`, aquí **sí** se indexan con la paleta, pero la
mayoría de los modelos de CS 1.5 son en realidad BMP de 8 bits con su propia
tabla de color... salvo que el motor los convierta con `palette.lmp`. En este
proyecto se usa la misma paleta que para los mapas.

## 3. Animación

`mstudioseqdesc_t` (176 B) y `mstudioanim_t` (12 B por hueso) tienen sus propios
offsets, y el decodificador RLE es el trozo más delicado del formato. Está
explicado aparte, con el algoritmo completo, en
[`ANIMACIONES.md`](ANIMACIONES.md).

Los tres offsets que hay que clavar:

```
fps       @ 32     (float32)
numframes @ 56     (int32)   <- no en 36
numblends @ 120    (int32)
animindex @ 124    (int32)   <- absoluto; no en 128
```

## 4. Escala y ejes

- **GoldSrc**: 1 unidad ≈ 0.025 m. `+X` este, `+Y` norte, `+Z` arriba.
- **Godot**: `+X` este, `+Y` arriba, `+Z` hacia el sur.
- Conversión usada: `(x, z, -y) * 0.025`.

## 5. Cómo verificarlo tú

```bash
python3 tools/cs15_validate.py --map de_dust2 --model gign
```

Compara los números con la tabla de arriba y mira los PNG de
`docs/previews/`: si la geometría se dibuja, los offsets están bien.
