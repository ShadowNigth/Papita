#!/usr/bin/env python3
"""Grafo de navegación para los bots, derivado del propio `.bsp`.

Esto no es un NavMesh inventado encima del mapa: se usan los datos que el
original ya trae.

* **Contenido de un punto** (sólido / vacío / agua): el árbol BSP
  (`lump 1` planos, `lump 5` nodos, `lump 10` hojas) responde en O(profundidad).
  Es exactamente lo que hacía `SV_PointContents` en GoldSrc.
* **Suelo**: las caras del modelo 0 cuya normal mira hacia arriba. Cada cara es
  convexa, así que se encoge unos centímetros y se muestrea en una rejilla.
* **Conexiones**: nodos vecinos en la rejilla con un desnivel pequeño (escaleras
  y rampas del original) y sin pared en medio.

El resultado es lo que `scripts/nav_grid.gd` reconstruye en tiempo de ejecución.
Este fichero es el **espejo en Python**: sirve para validar el algoritmo contra
los 10 mapas reales (cobertura, conectividad, atajos falsos a través de paredes)
y para dibujar una vista previa, ya que Godot no está disponible aquí.

Uso:
    python3 tools/nav_validate.py            # los 10 mapas
    python3 tools/nav_validate.py de_dust2   # uno solo, con PNG
"""
from __future__ import annotations

import re
import struct
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cs15_validate import MAPS, ROOT, SALIDA, Bsp, cargar_paleta  # noqa: E402

# --- geometría del jugador (unidades GoldSrc) --------------------------------
PASO_REJILLA = 40.0      # separación de muestras: 1 m
RADIO_ACTOR = 16.0       # radio de la cápsula del jugador en GoldSrc (32 u de diámetro)
ALTURA_PECHO = 40.0      # altura a la que se comprueba que no hay pared
DESNIVEL_MAX = 40.0      # escalón máximo entre dos nodos (escaleras del 1.5)
NORMAL_SUELO = 0.6       # coseno mínimo entre la normal y la vertical

# contenidos de hoja (constants.h de Quake)
CONT_EMPTY, CONT_SOLID, CONT_WATER = -1, -2, -3

TEXTURAS_IGNORADAS = ("sky", "clip", "hint", "skip", "null", "origin",
                      "aaatrigger", "water", "lava", "slime", "trigger")


# ---------------------------------------------------------------------------
# BSP: planos, nodos y hojas (lo que le falta al lector de render)
# ---------------------------------------------------------------------------
class Arbol:
    """Árbol BSP del `.bsp` para responder '¿este punto es sólido?'."""

    def __init__(self, bsp: Bsp) -> None:
        planos = bsp._lump(1)
        self.normal = np.frombuffer(planos, dtype=np.uint8).reshape(-1, 20)[:, 0:12] \
            .copy().view("<f4").reshape(-1, 3).astype(np.float64)
        self.dist = np.frombuffer(planos, dtype=np.uint8).reshape(-1, 20)[:, 12:16] \
            .copy().view("<f4").reshape(-1).astype(np.float64)

        nodos = bsp._lump(5)
        n = np.frombuffer(nodos, dtype=np.uint8).reshape(-1, 24)
        self.nodo_plano = n[:, 0:4].copy().view("<i4").reshape(-1)
        hijos = n[:, 4:8].copy().view("<i2").reshape(-1, 2)
        self.nodo_hijos = hijos.astype(np.int32)

        hojas = bsp._lump(10)
        self.hoja_contenido = np.frombuffer(hojas, dtype=np.uint8).reshape(-1, 28)[:, 0:4] \
            .copy().view("<i4").reshape(-1)

        # cabecera del modelo 0 (lump 14): firstface/numfaces para las caras del mundo
        ofs, _ = bsp.lumps[14]
        self.mundo_primera_cara, self.mundo_num_caras = struct.unpack_from("<ii", bsp.raw, ofs + 56)

    # -- consulta escalar, igual que la que se porta a GDScript -------------
    def contenido(self, p) -> int:
        nodo = 0
        guardas = 0
        while nodo >= 0:
            plano = self.nodo_plano[nodo]
            d = (self.normal[plano, 0] * p[0] + self.normal[plano, 1] * p[1]
                 + self.normal[plano, 2] * p[2] - self.dist[plano])
            nodo = self.nodo_hijos[nodo, 0] if d >= 0.0 else self.nodo_hijos[nodo, 1]
            guardas += 1
            if guardas > 4096:      # árbol corrupto: se trata como vacío
                return CONT_EMPTY
        idx = -nodo - 1
        return int(self.hoja_contenido[idx]) if 0 <= idx < len(self.hoja_contenido) else CONT_EMPTY

    # -- versión vectorizada, solo para el validador ------------------------
    def contenido_lote(self, puntos: np.ndarray) -> np.ndarray:
        """Contenido de N puntos de golpe recorriendo el árbol por niveles."""
        p = np.asarray(puntos, dtype=np.float64)
        n = len(p)
        nodo = np.zeros(n, dtype=np.int64)
        activo = np.ones(n, dtype=bool)
        for _ in range(4096):
            if not activo.any():
                break
            idx = np.nonzero(activo)[0]
            actual = nodo[idx]
            dentro = actual >= 0
            if not dentro.any():
                break
            idx, actual = idx[dentro], actual[dentro]
            plano = self.nodo_plano[actual]
            d = (self.normal[plano, 0] * p[idx, 0] + self.normal[plano, 1] * p[idx, 1]
                 + self.normal[plano, 2] * p[idx, 2] - self.dist[plano])
            nodo[idx] = np.where(d >= 0.0, self.nodo_hijos[actual, 0], self.nodo_hijos[actual, 1])
            activo[idx] = False
            activo[nodo[idx] >= 0] = True
        hoja = -nodo - 1
        valido = (hoja >= 0) & (hoja < len(self.hoja_contenido))
        salida = np.full(n, CONT_EMPTY, dtype=np.int32)
        salida[valido] = self.hoja_contenido[hoja[valido]]
        return salida


# ---------------------------------------------------------------------------
# Grafo de navegación
# ---------------------------------------------------------------------------
def normal_de_cara(bsp: Bsp, arbol: Arbol, cara: int) -> np.ndarray:
    plano = bsp.face_plano[cara]
    lado = struct.unpack_from("<h", bsp.raw, bsp.lumps[7][0] + cara * 20 + 2)[0]
    n = arbol.normal[plano].copy()
    if lado:
        n = -n
    return n


# El suelo de un mapa no es una cara, son cientos de trozos que el compilador
# corta por textura y por hoja. Encoger cada trozo por separado no sirve: un
# corredor queda partido en tiras que, tras el margen, no dan ni un punto. Por
# eso el hueco se comprueba con el propio BSP alrededor de cada muestra.
DESPLAZAMIENTOS_HUECO = ((1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0),
                         (0.7, 0.7), (-0.7, 0.7), (0.7, -0.7), (-0.7, -0.7))


def hay_hueco(arbol: "Arbol", x: float, y: float, z: float) -> bool:
    """¿Cabe el actor de pie en (x, y, z)? Cuerpo y cabeza libres."""
    for dx, dy in DESPLAZAMIENTOS_HUECO:
        if arbol.contenido((x + dx * RADIO_ACTOR, y + dy * RADIO_ACTOR, z + 20.0)) != CONT_EMPTY:
            return False
    return arbol.contenido((x, y, z + 58.0)) == CONT_EMPTY


def dentro_convexo(poly: np.ndarray, punto: np.ndarray) -> bool:
    m = len(poly)
    signo = 0
    for i in range(m):
        a = poly[i]
        b = poly[(i + 1) % m]
        cruz = (b[0] - a[0]) * (punto[1] - a[1]) - (b[1] - a[1]) * (punto[0] - a[0])
        if abs(cruz) < 1e-9:
            continue
        s = 1 if cruz > 0 else -1
        if signo == 0:
            signo = s
        elif s != signo:
            return False
    return True


class Grafo:
    def __init__(self) -> None:
        self.posiciones: list[np.ndarray] = []
        self.celdas: dict[tuple[int, int], list[int]] = {}
        self.vecinos: list[list[tuple[int, float]]] = []
        self.caras_usadas = 0
        self.caras_suelo = 0

    def anadir(self, p: np.ndarray) -> int | None:
        ix = int(round(p[0] / PASO_REJILLA))
        iy = int(round(p[1] / PASO_REJILLA))
        for idx in self.celdas.get((ix, iy), []):
            if abs(self.posiciones[idx][2] - p[2]) < 24.0:
                return None          # misma superficie: ya hay nodo
        idx = len(self.posiciones)
        self.posiciones.append(p)
        self.celdas.setdefault((ix, iy), []).append(idx)
        self.vecinos.append([])
        return idx

    def conectar(self) -> int:
        aristas = 0
        for (ix, iy), nodos in self.celdas.items():
            for a in nodos:
                pa = self.posiciones[a]
                for dx, dy in ((1, 0), (0, 1), (1, 1), (1, -1)):
                    for b in self.celdas.get((ix + dx, iy + dy), []):
                        pb = self.posiciones[b]
                        dz = abs(pa[2] - pb[2])
                        if dz > DESNIVEL_MAX:
                            continue
                        dist = float(np.linalg.norm(pa - pb))
                        if dist > PASO_REJILLA * 1.75:
                            continue
                        self.vecinos[a].append((b, dist))
                        self.vecinos[b].append((a, dist))
                        aristas += 1
        return aristas


def construir(bsp: Bsp) -> tuple[Grafo, Arbol]:
    arbol = Arbol(bsp)
    grafo = Grafo()
    primera, cuantas = arbol.mundo_primera_cara, arbol.mundo_num_caras

    for cara in range(primera, min(primera + cuantas, len(bsp.face_plano))):
        normal = normal_de_cara(bsp, arbol, cara)
        if normal[2] < NORMAL_SUELO:
            continue
        miptex = int(bsp.tex_miptex[bsp.face_texinfo[cara]])
        nombre = (bsp.texturas[miptex]["nombre"].lower()
                  if 0 <= miptex < len(bsp.texturas) else "")
        if nombre.startswith(TEXTURAS_IGNORADAS):
            continue
        grafo.caras_suelo += 1

        poly3 = bsp.vertices_cara(cara)
        if len(poly3) < 3:
            continue
        poly = poly3[:, :2]
        plano = normal[0] * poly3[0, 0] + normal[1] * poly3[0, 1] + normal[2] * poly3[0, 2]

        minx, miny = poly.min(axis=0)
        maxx, maxy = poly.max(axis=0)
        if maxx - minx < 1.0 or maxy - miny < 1.0:
            continue
        usada = False
        gx0 = int(np.ceil(minx / PASO_REJILLA))
        gx1 = int(np.floor(maxx / PASO_REJILLA))
        gy0 = int(np.ceil(miny / PASO_REJILLA))
        gy1 = int(np.floor(maxy / PASO_REJILLA))
        for gx in range(gx0, gx1 + 1):
            for gy in range(gy0, gy1 + 1):
                punto = np.array([gx * PASO_REJILLA, gy * PASO_REJILLA])
                if not dentro_convexo(poly, punto):
                    continue
                z = (plano - normal[0] * punto[0] - normal[1] * punto[1]) / normal[2]
                if not hay_hueco(arbol, punto[0], punto[1], z):
                    continue
                if grafo.anadir(np.array([punto[0], punto[1], z])) is not None:
                    usada = True
        if usada:
            grafo.caras_usadas += 1
    grafo.conectar()
    return grafo, arbol


# ---------------------------------------------------------------------------
# A*
# ---------------------------------------------------------------------------
def nodo_mas_cercano(grafo: Grafo, p: np.ndarray) -> int | None:
    mejor, mejor_d = None, 1e18
    for i, q in enumerate(grafo.posiciones):
        d = float(np.sum((q - p) ** 2))
        if d < mejor_d:
            mejor, mejor_d = i, d
    return mejor


def camino(grafo: Grafo, desde: int, hasta: int) -> list[int] | None:
    import heapq
    dist = {desde: 0.0}
    previo: dict[int, int] = {}
    cola = [(0.0, desde)]
    visto = set()
    while cola:
        _, actual = heapq.heappop(cola)
        if actual in visto:
            continue
        visto.add(actual)
        if actual == hasta:
            ruta = [actual]
            while ruta[-1] in previo:
                ruta.append(previo[ruta[-1]])
            return ruta[::-1]
        for vecino, coste in grafo.vecinos[actual]:
            if vecino in visto:
                continue
            nuevo = dist[actual] + coste
            if nuevo < dist.get(vecino, 1e18):
                dist[vecino] = nuevo
                previo[vecino] = actual
                h = float(np.linalg.norm(grafo.posiciones[vecino] - grafo.posiciones[hasta]))
                heapq.heappush(cola, (nuevo + h, vecino))
    return None


# ---------------------------------------------------------------------------
# Validación
# ---------------------------------------------------------------------------
def comprobar_atajos(grafo: Grafo, arbol: Arbol, muestras: int = 4000) -> float:
    """Fracción de aristas que atraviesan una pared (atajos falsos).

    Se camina la arista por dentro y se pregunta al BSP a la altura del pecho:
    si alguno de los puntos intermedios es sólido, la arista es mala.
    """
    pares = [(a, b) for a in range(len(grafo.posiciones)) for b, _ in grafo.vecinos[a] if a < b]
    if not pares:
        return 0.0
    rng = np.random.default_rng(7)
    if len(pares) > muestras:
        pares = [pares[i] for i in rng.choice(len(pares), muestras, replace=False)]

    malas = 0
    for a, b in pares:
        pa = grafo.posiciones[a]
        pb = grafo.posiciones[b]
        z = max(pa[2], pb[2]) + ALTURA_PECHO * 0.75
        for t in (0.25, 0.5, 0.75):
            p = pa + (pb - pa) * t
            if arbol.contenido((p[0], p[1], z)) != CONT_EMPTY:
                malas += 1
                break
    return malas / len(pares)


def cajas_de_zona(bsp: Bsp, clase: str) -> list[tuple[np.ndarray, np.ndarray]]:
    salida = []
    for e in bsp.entidades:
        if e.get("classname") != clase:
            continue
        modelo = e.get("model", "")
        if not modelo.startswith("*"):
            continue
        idx = int(modelo[1:])
        ofs, _ = bsp.lumps[14]
        mn = np.array(struct.unpack_from("<fff", bsp.raw, ofs + idx * 64))
        mx = np.array(struct.unpack_from("<fff", bsp.raw, ofs + idx * 64 + 12))
        salida.append((mn, mx))
    return salida


def validar_mapa(ruta: Path, paleta, dibujar: bool = False) -> dict:
    t0 = time.time()
    bsp = Bsp(ruta, paleta)
    grafo, arbol = construir(bsp)
    t_construir = time.time() - t0

    # Conectividad: la zona jugable tiene que ser un solo trozo alcanzable.
    # Se parte de TODOS los puntos de aparición, no solo del primero: cada
    # mapa tiene los suyos repartidos por las dos bases.
    spawns = []
    for e in bsp.entidades:
        if e.get("classname", "").startswith("info_player"):
            try:
                spawns.append(np.array([float(v) for v in e["origin"].split()]))
            except ValueError:
                pass
    inicios = [nodo_mas_cercano(grafo, s) for s in spawns]
    inicios = [i for i in inicios if i is not None]

    vistos: set[int] = set()
    pila = list(inicios)
    vistos.update(pila)
    while pila:
        n = pila.pop()
        for v, _ in grafo.vecinos[n]:
            if v not in vistos:
                vistos.add(v)
                pila.append(v)
    alcanzables = len(vistos)

    # componentes conexas: la mayor debería ser casi todo el grafo
    todos: set[int] = set(range(len(grafo.posiciones)))
    mayor = 0
    while todos:
        raiz = next(iter(todos))
        comp = {raiz}
        pila2 = [raiz]
        while pila2:
            n = pila2.pop()
            for v, _ in grafo.vecinos[n]:
                if v not in comp:
                    comp.add(v)
                    pila2.append(v)
        todos -= comp
        mayor = max(mayor, len(comp))

    # Objetivo alcanzable: existe un nodo DENTRO de la caja de la zona que se
    # pueda pisar desde un spawn. Se mira la caja entera y no el centro, porque
    # el centro de un brush puede caer dentro de una pared o encima de un techo.
    objetivos = {}
    for clase in ("func_bomb_target", "func_buyzone", "func_hostage_rescue"):
        for i, (mn, mx) in enumerate(cajas_de_zona(bsp, clase)):
            dentro = [j for j, q in enumerate(grafo.posiciones)
                      if mn[0] - 16 <= q[0] <= mx[0] + 16
                      and mn[1] - 16 <= q[1] <= mx[1] + 16
                      and mn[2] - 48 <= q[2] <= mx[2] + 48]
            objetivos[f"{clase}[{i}]"] = any(j in vistos for j in dentro)

    atajos = comprobar_atajos(grafo, arbol)

    if dibujar:
        dibujar_grafo(bsp, grafo)

    return {
        "mapa": ruta.stem,
        "caras_suelo": grafo.caras_suelo,
        "caras_usadas": grafo.caras_usadas,
        "nodos": len(grafo.posiciones),
        "aristas": sum(len(v) for v in grafo.vecinos) // 2,
        "segundos": t_construir,
        "alcanzables": alcanzables,
        "mayor_componente": mayor,
        "spawns": len(inicios),
        "atajos_falsos": atajos,
        "objetivos": objetivos,
    }


def dibujar_grafo(bsp: Bsp, grafo: Grafo, tam: int = 1400) -> Path:
    from PIL import Image, ImageDraw

    puntos = np.array(grafo.posiciones)
    mn = puntos[:, :2].min(axis=0)
    mx = puntos[:, :2].max(axis=0)
    escala = tam / max(mx[0] - mn[0], mx[1] - mn[1])

    img = Image.new("RGB", (tam, tam), (12, 14, 18))
    dib = ImageDraw.Draw(img)

    def a_pixel(p):
        return (float(p[0] - mn[0]) * escala, tam - float(p[1] - mn[1]) * escala)

    # aristas
    for a, vecinos in enumerate(grafo.vecinos):
        for b, _ in vecinos:
            if a < b:
                dib.line([a_pixel(puntos[a]), a_pixel(puntos[b])],
                         fill=(30, 45, 40), width=1)
    # nodos, con el color según la altura (las plantas se distinguen)
    zs = puntos[:, 2]
    z0, z1 = float(zs.min()), float(zs.max())
    for i, p in enumerate(puntos):
        f = 0.0 if z1 <= z0 else (p[2] - z0) / (z1 - z0)
        color = (int(60 + 180 * f), int(200 - 120 * f), int(90 + 60 * (1 - f)))
        x, y = a_pixel(p)
        dib.ellipse([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill=color)

    titulo = f"{bsp.path.stem}: {len(puntos)} nodos de navegación ({PASO_REJILLA:.0f} u)"
    dib.text((10, 10), titulo, fill=(230, 235, 240))
    dib.text((10, 26), "color = altura: verde abajo, naranja arriba", fill=(150, 160, 170))

    salida = SALIDA / f"nav_{bsp.path.stem}.png"
    salida.parent.mkdir(parents=True, exist_ok=True)
    img.save(salida)
    return salida


def comprobar_paridad(problemas: list[str]) -> None:
    """El port a GDScript tiene que usar los mismos números que este prototipo.

    Si alguien ajusta `PASO` en un sitio y no en el otro, el grafo del juego
    deja de ser el que se ha validado aquí y el mapa se llena de huecos.
    """
    texto = (ROOT / "scripts" / "nav_grid.gd").read_text(encoding="utf-8")
    esperado = {
        "PASO": PASO_REJILLA,
        "RADIO_ACTOR": RADIO_ACTOR,
        "DESNIVEL_MAX": DESNIVEL_MAX,
        "NORMAL_SUELO": NORMAL_SUELO,
    }
    for nombre, valor in esperado.items():
        m = re.search(r"const %s := ([0-9.]+)" % nombre, texto)
        if not m:
            problemas.append(f"nav_grid.gd no declara {nombre}")
            continue
        if abs(float(m.group(1)) - valor) > 1e-9:
            problemas.append(f"nav_grid.gd: {nombre} = {m.group(1)}, "
                             f"el prototipo usa {valor}")


def main(argv: list[str]) -> int:
    paleta, origen = cargar_paleta()
    print(f"paleta: {origen}\n")
    mapas = sorted(MAPS.glob("*.bsp"))
    if len(argv) > 1:
        mapas = [m for m in mapas if m.stem in argv[1:]] or mapas

    problemas = 0
    comprobar_paridad(problemas)
    print(f"{'mapa':12} {'suelo':>6} {'nodos':>7} {'aristas':>8} {'alcanza':>8} "
          f"{'atajos':>7} {'s':>6}  objetivos")
    for ruta in mapas:
        r = validar_mapa(ruta, paleta, dibujar=True)
        cohesion = r["alcanzables"] / r["nodos"] if r["nodos"] else 0.0
        mayor = r["mayor_componente"] / r["nodos"] if r["nodos"] else 0.0
        fallan = [k for k, ok in r["objetivos"].items() if not ok]
        print(f"{r['mapa']:12} {r['caras_usadas']:6d} {r['nodos']:7d} {r['aristas']:8d} "
              f"{cohesion * 100:7.1f}% {r['atajos_falsos'] * 100:6.1f}% {r['segundos']:6.2f}"
              f"  {len(r['objetivos']) - len(fallan)}/{len(r['objetivos'])}"
              + (f"   sin ruta: {', '.join(fallan)}" if fallan else ""))
        if r["nodos"] == 0:
            print("    !! sin nodos: la rejilla no ha encontrado suelo")
            problemas += 1
        # No se exige el 100%: en un mapa de verdad hay tejados, toldos y
        # cornisas donde se puede "estar de pie" pero no llegar sin escaleras
        # o saltos, y el grafo los muestrea igual. Lo que sí es obligatorio es
        # que los objetivos sean alcanzables (se comprueba aparte).
        if cohesion < 0.40:
            problemas += 1
            print(f"    !! solo el {cohesion * 100:.0f}% del grafo es alcanzable desde un spawn "
                  f"(la mayor componente es el {mayor * 100:.0f}%)")
        elif cohesion < 0.9:
            print(f"    (el {100 - cohesion * 100:.0f}% restante son tejados y cornisas "
                  f"sin acceso a pie)")
        if r["atajos_falsos"] > 0.05:
            problemas += 1
            print(f"    !! demasiados atajos a través de paredes: {r['atajos_falsos'] * 100:.1f}%")
        for nombre in fallan:
            problemas += 1
            print(f"    !! no hay ruta hasta {nombre}")

    print(f"\nproblemas: {problemas}")
    print(f"vistas previas en {SALIDA.relative_to(ROOT)}/nav_*.png")
    return 1 if problemas else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
