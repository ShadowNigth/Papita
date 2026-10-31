#!/usr/bin/env python3
"""Espejo en Python de los parsers de `scripts/` (GDScript) + previsualizacion.

Sirve para dos cosas:

1. **Validar** el formato contra los assets reales (10 .bsp, 96 .mdl) sin abrir
   Godot: indices fuera de rango, lumps corruptos, caras degeneradas, huesos
   inexistentes, secuencias sin cuadros...
2. **Ensenar** el resultado: renderiza un plano cenital de cada mapa (con
   texturas y lightmaps) y una vista frontal de cada modelo, para comprobar que
   la geometria y las texturas se leen bien antes de tocar el motor.

La logica de offsets es la misma que la de `scripts/bsp_reader.gd` y
`scripts/mdl_reader.gd`: si esto cuadra, aquellos tambien.

    python3 tools/cs15_validate.py                 # informe + PNGs
    python3 tools/cs15_validate.py --map de_dust2  # un mapa
    python3 tools/cs15_validate.py --no-render     # solo validar
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
MAPS = ROOT / "assets" / "maps" / "cs15"
MODELS = ROOT / "assets" / "models" / "cs15"
SALIDA = ROOT / "docs" / "previews"

LUMP_ENTIDADES, LUMP_PLANOS, LUMP_TEXTURAS, LUMP_VERTICES = 0, 1, 2, 3
LUMP_NODOS, LUMP_TEXINFO, LUMP_CARAS, LUMP_LUZ = 5, 6, 7, 8
LUMP_HOJAS, LUMP_MARKSURF, LUMP_ARISTAS, LUMP_SURFEDGES, LUMP_MODELOS = 10, 11, 12, 13, 14


# --------------------------------------------------------------------------
# paleta
# --------------------------------------------------------------------------
def paleta_generada() -> np.ndarray:
    """Misma paleta aproximada que genera el juego si no hay palette.lmp."""
    pal = np.zeros((256, 3), dtype=np.uint8)
    i = 0
    for r in range(6):
        for g in range(6):
            for b in range(6):
                pal[i] = (r * 51, g * 51, b * 51)
                i += 1
    for k in range(40):
        v = min(255, k * 255 // 39)
        pal[i] = (v, v, v)
        i += 1
    return pal


def cargar_paleta() -> tuple[np.ndarray, str]:
    for cand in (ROOT / "assets" / "valve" / "gfx" / "palette.lmp",
                 ROOT / "assets" / "gfx" / "palette.lmp"):
        if cand.is_file() and cand.stat().st_size >= 768:
            raw = np.frombuffer(cand.read_bytes()[:768], dtype=np.uint8)
            return raw.reshape(256, 3), str(cand.relative_to(ROOT))
    return paleta_generada(), "generada (aproximada)"


# --------------------------------------------------------------------------
# BSP v30
# --------------------------------------------------------------------------
class Bsp:
    def __init__(self, path: Path, paleta: np.ndarray):
        self.path = path
        self.raw = path.read_bytes()
        self.paleta = paleta
        self.version = struct.unpack_from("<i", self.raw, 0)[0]
        self.lumps = [struct.unpack_from("<ii", self.raw, 4 + i * 8) for i in range(15)]
        self._leer_entidades()
        self._leer_vertices()
        self._leer_texinfo()
        self._leer_texturas()
        self._leer_caras()

    def _lump(self, i: int) -> bytes:
        ofs, ln = self.lumps[i]
        return self.raw[ofs:ofs + ln]

    def _leer_entidades(self) -> None:
        texto = self._lump(LUMP_ENTIDADES).split(b"\0")[0].decode("latin1", "replace")
        self.entidades: list[dict] = []
        cur: dict = {}
        for linea in texto.split("\n"):
            linea = linea.strip()
            if linea == "{":
                cur = {}
            elif linea == "}":
                if cur:
                    self.entidades.append(cur)
            elif linea.startswith('"'):
                trozos = linea.split('"')
                if len(trozos) >= 4:
                    cur[trozos[1]] = trozos[3]

    def _leer_vertices(self) -> None:
        datos = self._lump(LUMP_VERTICES)
        self.vertices = np.frombuffer(datos, dtype="<f4").reshape(-1, 3).astype(np.float64)

    def _leer_texinfo(self) -> None:
        datos = self._lump(LUMP_TEXINFO)
        self.texinfo = np.frombuffer(datos, dtype=np.uint8).reshape(-1, 40)
        self.tex_vecs = self.texinfo[:, 0:32].copy().view("<f4").reshape(-1, 8).astype(np.float64)
        self.tex_miptex = self.texinfo[:, 32:36].copy().view("<i4").reshape(-1)

    def _leer_texturas(self) -> None:
        tofs, _ = self.lumps[LUMP_TEXTURAS]
        n = struct.unpack_from("<i", self.raw, tofs)[0]
        self.texturas: list[dict] = []
        for i in range(n):
            off = struct.unpack_from("<i", self.raw, tofs + 4 + i * 4)[0]
            base = tofs + off
            nombre = self.raw[base:base + 16].split(b"\0")[0].decode("latin1")
            w, h = struct.unpack_from("<ii", self.raw, base + 16)
            offsets = struct.unpack_from("<iiii", self.raw, base + 24)
            tex = {"nombre": nombre, "ancho": w, "alto": h, "externa": offsets[0] == -1,
                   "media": np.array((160, 150, 140), dtype=np.uint8), "rgb": None}
            if not tex["externa"] and offsets[0] and w > 0 and h > 0:
                mip = base + offsets[0]
                datos = self.raw[mip:mip + w * h]
                if len(datos) == w * h:
                    idx = np.frombuffer(datos, dtype=np.uint8)
                    rgb = self.paleta[idx].reshape(h, w, 3)
                    tex["rgb"] = rgb
                    tex["media"] = rgb.reshape(-1, 3).mean(axis=0).astype(np.uint8)
            self.texturas.append(tex)

    def _leer_caras(self) -> None:
        datos = self._lump(LUMP_CARAS)
        self.caras = np.frombuffer(datos, dtype=np.uint8).reshape(-1, 20)
        self.face_plano = self.caras[:, 0:2].copy().view("<i2").reshape(-1)
        self.face_firstedge = self.caras[:, 4:8].copy().view("<i4").reshape(-1)
        self.face_numedges = self.caras[:, 8:10].copy().view("<i2").reshape(-1)
        self.face_texinfo = self.caras[:, 10:12].copy().view("<i2").reshape(-1)
        self.face_lightofs = self.caras[:, 16:20].copy().view("<i4").reshape(-1)
        self.surfedges = np.frombuffer(self._lump(LUMP_SURFEDGES), dtype="<i4")
        self.aristas = np.frombuffer(self._lump(LUMP_ARISTAS), dtype="<u2").reshape(-1, 2)

    # -- geometria de una cara -------------------------------------------
    def vertices_cara(self, i: int) -> np.ndarray:
        ini = self.face_firstedge[i]
        n = self.face_numedges[i]
        idx = self.surfedges[ini:ini + n].astype(np.int64)
        v = np.where(idx >= 0, self.aristas[np.abs(idx), 0], self.aristas[np.abs(idx), 1])
        return self.vertices[v]

    def lightmap_cara(self, i: int) -> np.ndarray | None:
        """Devuelve el lightmap de la cara como array (h,w,3) en 0..1."""
        off = self.face_lightofs[i]
        if off < 0:
            return None
        ti = self.face_texinfo[i]
        if not (0 <= ti < len(self.tex_vecs)):
            return None
        verts = self.vertices_cara(i)
        if len(verts) == 0:
            return None
        vecs = self.tex_vecs[ti]
        s = verts @ vecs[0:3] + vecs[3]
        t = verts @ vecs[4:7] + vecs[7]
        bmin_s, bmin_t = math.floor(s.min() / 16), math.floor(t.min() / 16)
        bmax_s, bmax_t = math.ceil(s.max() / 16), math.ceil(t.max() / 16)
        w = (bmax_s - bmin_s) + 1
        h = (bmax_t - bmin_t) + 1
        if w <= 0 or h <= 0 or w > 512 or h > 512:
            return None
        n = w * h * 3
        datos = self.raw[self.lumps[LUMP_LUZ][0] + off: self.lumps[LUMP_LUZ][0] + off + n]
        if len(datos) < n:
            return None
        return np.frombuffer(datos, dtype=np.uint8).reshape(h, w, 3).astype(np.float64) / 255.0

    # -- validacion -------------------------------------------------------
    def validar(self) -> dict:
        problemas: list[str] = []
        if self.version != 30:
            problemas.append(f"version {self.version} != 30")
        for i, (ofs, ln) in enumerate(self.lumps):
            if ofs < 0 or ln < 0 or ofs + ln > len(self.raw):
                problemas.append(f"lump {i} fuera de rango ({ofs}+{ln})")

        nv = len(self.vertices)
        if self.surfedges.size and np.abs(self.surfedges).max() >= len(self.aristas):
            problemas.append("surfedge apunta a una arista inexistente")
        if len(self.aristas) and self.aristas.max() >= nv:
            problemas.append("arista apunta a un vertice inexistente")

        malas = 0
        for i in range(len(self.face_texinfo)):
            ti = self.face_texinfo[i]
            if not (0 <= ti < len(self.tex_vecs)) or self.tex_miptex[ti] >= len(self.texturas):
                malas += 1
        if malas:
            problemas.append(f"{malas} caras con texinfo/textura invalida")

        degeneradas = int((self.face_numedges < 3).sum())
        if degeneradas:
            problemas.append(f"{degeneradas} caras con menos de 3 vertices")

        clases = Counter(e.get("classname", "?") for e in self.entidades)
        spawns = clases.get("info_player_start", 0) + clases.get("info_player_deathmatch", 0)
        if spawns == 0:
            problemas.append("sin puntos de aparicion")

        return {
            "fichero": self.path.name,
            "version": self.version,
            "vertices": nv,
            "caras": len(self.face_texinfo),
            "texturas": len(self.texturas),
            "texturas_externas": sum(1 for t in self.texturas if t["externa"]),
            "entidades": len(self.entidades),
            "spawns": spawns,
            "bomb_targets": clases.get("func_bomb_target", 0),
            "rehenes": clases.get("hostage_entity", 0),
            "problemas": problemas,
        }


# --------------------------------------------------------------------------
# render cenital de un mapa
# --------------------------------------------------------------------------
def render_mapa(bsp: Bsp, salida: Path, tam: int = 1400) -> Path:
    """Plano de planta: solo superficies horizontales, gana la mas baja.

    Un volcado cenital de todas las caras sale como una losa gris, porque los
    techos tapan los suelos. Aqui se pintan de arriba a abajo las caras cuyo
    normal apunta hacia arriba, de modo que al final queda visible el nivel
    inferior (la planta calle). Encima se marcan spawns y objetivos leyendo las
    entidades del .bsp.
    """
    caras = []
    for i in range(len(bsp.face_texinfo)):
        verts = bsp.vertices_cara(i)
        if len(verts) < 3:
            continue
        n = np.cross(verts[1] - verts[0], verts[2] - verts[0])
        norma = np.linalg.norm(n)
        if norma < 1e-6:
            continue
        n = n / norma
        if n[2] < 0.6:          # solo suelos (no paredes ni techos)
            continue
        ti = bsp.face_texinfo[i]
        if not (0 <= ti < len(bsp.tex_vecs)):
            continue
        color = bsp.texturas[bsp.tex_miptex[ti]]["media"].astype(np.float64)
        lm = bsp.lightmap_cara(i)
        luz = float(np.clip(lm.mean() * 2.0, 0.45, 1.25)) if lm is not None and lm.size else 1.0
        caras.append((float(verts[:, 2].mean()), color * luz, verts[:, [0, 1]]))

    if not caras:
        img = Image.new("RGB", (tam, tam), (12, 14, 18))
        img.save(salida)
        return salida

    caras.sort(key=lambda c: -c[0])   # de arriba a abajo: el suelo queda encima
    xs = np.concatenate([c[2][:, 0] for c in caras])
    ys = np.concatenate([c[2][:, 1] for c in caras])
    minx, maxx, miny, maxy = xs.min(), xs.max(), ys.min(), ys.max()
    esc = (tam - 20) / max(maxx - minx, maxy - miny)

    def proy(x: float, y: float) -> tuple[float, float]:
        # GoldSrc: +Y arriba, -X al este. Se invierte el eje para verlo como el radar.
        return ((x - minx) * esc + 10, (maxy - y) * esc + 10)

    img = Image.new("RGB", (tam, tam), (10, 12, 16))
    dib = ImageDraw.Draw(img)
    for _, color, pts in caras:
        poly = [proy(x, y) for x, y in pts]
        if len(poly) < 3:
            continue
        c = tuple(int(v) for v in np.clip(color, 10, 255))
        borde = tuple(max(0, v - 14) for v in c)
        dib.polygon(poly, fill=c, outline=borde)

    marcadores = {
        "info_player_start": ((90, 160, 255), 5),
        "info_player_deathmatch": ((90, 160, 255), 3),
        "info_player_terrorist": ((255, 120, 90), 5),
        "info_player_counterterrorist": ((90, 160, 255), 5),
        "func_bomb_target": ((255, 170, 40), 12),
        "hostage_entity": ((255, 235, 90), 7),
    }
    for ent in bsp.entidades:
        clase = ent.get("classname", "")
        if clase not in marcadores:
            continue
        color, radio = marcadores[clase]
        try:
            x, y, z = (float(v) for v in ent.get("origin", "0 0 0").split())
        except ValueError:
            continue
        px, py = proy(x, y)
        dib.ellipse((px - radio, py - radio, px + radio, py + radio),
                    outline=color, width=2, fill=None if clase.startswith("func_") else color)

    salida.parent.mkdir(parents=True, exist_ok=True)
    img.save(salida)
    return salida


def montaje_texturas(bsp: Bsp, salida: Path, celda: int = 96) -> Path | None:
    con_rgb = [t for t in bsp.texturas if t["rgb"] is not None]
    if not con_rgb:
        return None
    cols = 8
    filas = (len(con_rgb) + cols - 1) // cols
    img = Image.new("RGB", (cols * celda, filas * celda), (20, 20, 20))
    for i, tex in enumerate(con_rgb[:cols * filas]):
        t = Image.fromarray(tex["rgb"]).resize((celda, celda), Image.NEAREST)
        img.paste(t, ((i % cols) * celda, (i // cols) * celda))
    salida.parent.mkdir(parents=True, exist_ok=True)
    img.save(salida)
    return salida


# --------------------------------------------------------------------------
# MDL v10
# --------------------------------------------------------------------------
class Mdl:
    def __init__(self, path: Path, paleta: np.ndarray):
        self.path = path
        self.raw = path.read_bytes()
        self.paleta = paleta
        r = self.raw
        self.ident = r[0:4].decode("latin1")
        self.version = struct.unpack_from("<i", r, 4)[0]
        self.nombre = r[8:72].split(b"\0")[0].decode("latin1")
        self.eyepos = struct.unpack_from("<3f", r, 76)
        self.min = struct.unpack_from("<3f", r, 88)
        self.max = struct.unpack_from("<3f", r, 100)
        self.numbones, self.boneindex = struct.unpack_from("<ii", r, 140)
        self.numseq, self.seqindex = struct.unpack_from("<ii", r, 164)
        self.numtex, self.textureindex = struct.unpack_from("<ii", r, 180)
        self.texturedata = struct.unpack_from("<i", r, 188)[0]
        self.numskinref, self.numskinfamilies, self.skinindex = struct.unpack_from("<iii", r, 192)
        self.numbodyparts, self.bodypartindex = struct.unpack_from("<ii", r, 204)
        self.bind_pose: list[np.ndarray] = []
        self._leer_huesos()
        self._leer_secuencias()
        self._leer_texturas()
        self._leer_cuerpos()

    def _leer_huesos(self) -> None:
        self.huesos = []
        for i in range(self.numbones):
            base = self.boneindex + i * 112
            if base + 112 > len(self.raw):
                break
            nombre = self.raw[base:base + 32].split(b"\0")[0].decode("latin1")
            padre = struct.unpack_from("<i", self.raw, base + 32)[0]
            # mstudiobone_t (112 B): name[32] parent@32 unused@36 ctrl[6]@40
            # value[6]@64 -> value[0..2] posicion, value[3..5] rotacion (rad)
            # scale[6]@88 -> escala de posicion y de rotacion
            value = struct.unpack_from("<6f", self.raw, base + 64)
            scale = struct.unpack_from("<6f", self.raw, base + 88)
            self.huesos.append({"nombre": nombre, "padre": padre,
                                "pos": value[0:3], "rot": value[3:6],
                                "value": value, "esc_raw": scale})

    def _leer_secuencias(self) -> None:
        self.secuencias = []
        for i in range(self.numseq):
            base = self.seqindex + i * 176
            if base + 176 > len(self.raw):
                break
            nombre = self.raw[base:base + 32].split(b"\0")[0].decode("latin1")
            # mstudioseqdesc_t: fps@32 flags@36 ... numframes@56 ... numblends@120 animindex@124
            fps = struct.unpack_from("<f", self.raw, base + 32)[0]
            cuadros = struct.unpack_from("<i", self.raw, base + 56)[0]
            numblends, animindex = struct.unpack_from("<ii", self.raw, base + 120)
            self.secuencias.append({"nombre": nombre, "fps": fps, "cuadros": cuadros,
                                    "blends": numblends, "animindex": animindex})

    def _leer_texturas(self) -> None:
        self.texturas = []
        for i in range(self.numtex):
            base = self.textureindex + i * 80
            if base + 80 > len(self.raw):
                break
            nombre = self.raw[base:base + 64].split(b"\0")[0].decode("latin1")
            flags, w, h, idx = struct.unpack_from("<iiii", self.raw, base + 64)
            rgb = None
            paleta_incrustada = False
            if 0 < idx < len(self.raw) and w > 0 and h > 0 and w * h < 4_000_000:
                fin_pixeles = idx + w * h
                datos = self.raw[idx:fin_pixeles]
                if len(datos) == w * h:
                    tabla = self.paleta
                    if fin_pixeles + 256 * 3 <= len(self.raw):
                        tabla = np.frombuffer(self.raw[fin_pixeles:fin_pixeles + 256 * 3],
                                              dtype=np.uint8).reshape(256, 3)
                        paleta_incrustada = True
                    rgb = tabla[np.frombuffer(datos, dtype=np.uint8)].reshape(h, w, 3)
            self.texturas.append({"nombre": nombre, "ancho": w, "alto": h,
                                  "rgb": rgb, "paleta_incrustada": paleta_incrustada})

    def _leer_cuerpos(self) -> None:
        """bodypart -> model -> mesh, con los offsets reales de los structs.

        mstudiomodel_t : name[64] type@64 radius@68 nummesh@72 meshindex@76
                         numverts@80 vertinfoindex@84 vertindex@88
        mstudiomesh_t  : numtris@0 triindex@4 skinref@8 numnorms@12 normindex@16
        Los indices de vertice son shorts y `triindex` es relativo a la malla.
        """
        self.mallas = []
        for bp in range(self.numbodyparts):
            base = self.bodypartindex + bp * 76
            if base + 76 > len(self.raw):
                continue
            nummodels = struct.unpack_from("<i", self.raw, base + 64)[0]
            modelindex = struct.unpack_from("<i", self.raw, base + 72)[0]
            for mo in range(nummodels):
                mbase = modelindex + mo * 112  # sizeof(mstudiomodel_t)
                if mbase + 112 > len(self.raw):
                    continue
                nummesh = struct.unpack_from("<i", self.raw, mbase + 72)[0]
                meshindex = struct.unpack_from("<i", self.raw, mbase + 76)[0]
                numverts = struct.unpack_from("<i", self.raw, mbase + 80)[0]
                vertinfo = struct.unpack_from("<i", self.raw, mbase + 84)[0]
                vertindex = struct.unpack_from("<i", self.raw, mbase + 88)[0]
                if numverts <= 0 or numverts > 65535:
                    continue
                verts = np.frombuffer(self.raw, dtype="<f4", count=numverts * 3,
                                      offset=vertindex).reshape(-1, 3).astype(np.float64)
                if not self.bind_pose:
                    self._calcular_bind_pose()
                # un byte por vertice: a que hueso pertenece
                hueso_de_vertice = self.raw[vertinfo:vertinfo + numverts]
                for m in range(nummesh):
                    mb = meshindex + m * 20
                    if mb + 20 > len(self.raw):
                        continue
                    numtris, triindex, skinref = struct.unpack_from("<iii", self.raw, mb)
                    tris = self._triangulos(triindex, numtris)  # triindex es absoluto
                    if len(verts) and tris:
                        self.mallas.append({"vertices": verts, "triangulos": tris,
                                            "skinref": skinref,
                                            "huesos": hueso_de_vertice})

    def _triangulos(self, pos: int, numtris: int) -> list[tuple[int, int, int]]:
        """Comandos de triangulos del formato GoldSrc.

        Cada comando empieza por `count` (short). Si es negativo es un fan, si
        es positivo un strip. Le siguen `abs(count)` vertices de **4 shorts**:
        (indice, normal, s, t). El indice es el primer short de cada grupo.
        Ref: xash3d-fwgs/ref/gl/gl_studio.c -> R_StudioGenerateNormals().
        """
        tris: list[tuple[int, int, int]] = []
        hechos = 0
        while hechos < numtris and pos + 2 <= len(self.raw):
            cnt = struct.unpack_from("<h", self.raw, pos)[0]
            pos += 2
            if cnt == 0:
                break
            n = abs(cnt)
            if n < 3 or pos + n * 8 > len(self.raw):
                break
            idx = [struct.unpack_from("<h", self.raw, pos + k * 8)[0] for k in range(n)]
            pos += n * 8
            if cnt < 0:  # fan
                for k in range(1, n - 1):
                    tris.append((idx[0], idx[k], idx[k + 1]))
                    hechos += 1
            else:        # strip
                for k in range(2, n):
                    if k % 2 == 0:
                        tris.append((idx[k - 2], idx[k - 1], idx[k]))
                    else:
                        tris.append((idx[k - 1], idx[k - 2], idx[k]))
                    hechos += 1
        return tris

    def _calcular_bind_pose(self) -> None:
        """Matrices 3x4 de la pose de reposo, componiendo la jerarquia.

        En StudioModel v10 el vertice se guarda en espacio LOCAL del hueso; el
        motor lo pasa a espacio de modelo en cada cuadro con la matriz del hueso
        (R_StudioSetupModel). Aqui se hace lo mismo con la pose de bind de
        `value`/`scale` para poder dibujar el modelo sin animar.
        """
        self.bind_pose: list[np.ndarray] = []
        for i, h in enumerate(self.huesos):
            # misma rotacion que el motor: cuaternion desde (pitch, yaw, roll)
            m = Mdl._matriz(list(h["pos"]), list(h["rot"]))
            # OJO: value[6]/scale[6] del hueso NO son un transform. `scale` es el
            # factor de compresion (1/256) de los controladores de hueso, no una
            # escala de la matriz; multiplicarla colapsa el modelo al origen.
            padre = h["padre"]
            if 0 <= padre < len(self.bind_pose):
                pm = self.bind_pose[padre]
                m = np.hstack([pm[:, :3] @ m[:, :3], (pm[:, :3] @ m[:, 3:4] + pm[:, 3:4])])
            self.bind_pose.append(m)

    def vertices_modelo(self, malla: dict) -> np.ndarray:
        """Vertices de una malla pasados a espacio de modelo con la bind pose."""
        verts = malla["vertices"]
        huesos = malla.get("huesos")
        if huesos is None or not self.bind_pose:
            return verts
        out = np.empty_like(verts)
        for i, v in enumerate(verts):
            b = huesos[i] if i < len(huesos) else 0
            m = self.bind_pose[b] if b < len(self.bind_pose) else self.bind_pose[0]
            out[i] = m[:, :3] @ v + m[:, 3]
        return out

    # ------------------------------------------------------------------
    # animacion (equivalente a R_StudioCalcBones + SV_StudioSetupBones)
    # ------------------------------------------------------------------
    def _canal(self, base: int, frame: int) -> tuple[int, int]:
        """Lee un canal RLE y devuelve los dos valores a interpolar.

        Port literal de R_StudioCalcBones (public/xash3d_mathlib.c): cada bloque
        empieza con un `mstudioanimvalue_t` de 2 bytes donde `num.valid` dice
        cuantos valores reales siguen y `num.total` cuantos cuadros cubren.
        """
        p = base
        valid = self.raw[p]
        total = self.raw[p + 1]
        j = frame
        if total < valid:
            j = 0
        while total <= j:
            j -= total
            p += (valid + 1) * 2
            valid = self.raw[p]
            total = self.raw[p + 1]
            if total < valid:
                j = 0

        def valor(celda: int) -> int:
            pos = p + celda * 2
            if pos + 2 > len(self.raw):
                return 0
            return struct.unpack_from("<h", self.raw, pos)[0]

        if valid > j:
            v1 = valor(j + 1)
            if valid > j + 1:
                v2 = valor(j + 2)
            elif total > j + 1:
                v2 = v1
            else:
                v2 = valor(valid + 2)
        else:
            v1 = valor(valid)
            v2 = v1 if total > j + 1 else valor(valid + 2)
        return v1, v2

    def _canal_bone(self, bone: dict, panim: int, canal: int, frame: int) -> tuple[float, float]:
        off = struct.unpack_from("<H", self.raw, panim + canal * 2)[0]
        base = bone["value"][canal]
        if off == 0:
            return base, base
        raw1, raw2 = self._canal(panim + off, frame)
        esc = bone["esc_raw"][canal]
        return base + raw1 * esc, base + raw2 * esc

    def pose(self, seq: int, frame: float) -> list[np.ndarray]:
        """Matrices 3x4 globales de cada hueso en la secuencia y cuadro dados."""
        if not (0 <= seq < len(self.secuencias)):
            return self.bind_pose
        desc = self.secuencias[seq]
        cuadros = max(1, int(desc["cuadros"]))
        f = frame % cuadros
        entero = int(f)
        s = f - entero
        tabla = desc["animindex"]
        if tabla <= 0 or tabla >= len(self.raw):
            return self.bind_pose

        locales: list[np.ndarray] = []
        for i, h in enumerate(self.huesos):
            panim = tabla + i * 12          # un mstudioanim_t (6 uint16) por hueso
            if panim + 12 > len(self.raw):
                locales.append(self._matriz(h["pos"], h["rot"]))
                continue
            p1, p2 = [], []
            for c in range(3):
                a, b = self._canal_bone(h, panim, c, entero)
                p1.append(a)
                p2.append(b)
            r1, r2 = [], []
            for c in range(3, 6):
                a, b = self._canal_bone(h, panim, c, entero)
                r1.append(a)
                r2.append(b)
            pos = np.array([p1[k] + (p2[k] - p1[k]) * s for k in range(3)])
            q1 = self._quat(r1)
            q2 = self._quat(r2)
            q = self._slerp(q1, q2, s)
            locales.append(self._matriz_quat(pos, q))

        globales: list[np.ndarray] = []
        for i, h in enumerate(self.huesos):
            padre = h["padre"]
            if 0 <= padre < len(globales):
                pm = globales[padre]
                m = np.hstack([pm[:, :3] @ locales[i][:, :3],
                               (pm[:, :3] @ locales[i][:, 3:4] + pm[:, 3:4])])
            else:
                m = locales[i]
            globales.append(m)
        return globales

    @staticmethod
    def _quat(angles: list[float]) -> np.ndarray:
        """Cuaternion GoldSrc studio=true desde (pitch, yaw, roll), en radianes."""
        sr, cr = math.sin(angles[0] * 0.5), math.cos(angles[0] * 0.5)
        sp, cp = math.sin(angles[1] * 0.5), math.cos(angles[1] * 0.5)
        sy, cy = math.sin(angles[2] * 0.5), math.cos(angles[2] * 0.5)
        return np.array([
            sr * cp * cy - cr * sp * sy,
            cr * sp * cy + sr * cp * sy,
            cr * cp * sy - sr * sp * cy,
            cr * cp * cy + sr * sp * sy,
        ])

    @staticmethod
    def _slerp(q1: np.ndarray, q2: np.ndarray, s: float) -> np.ndarray:
        d = float(np.dot(q1, q2))
        if d < 0.0:
            q2 = -q2
            d = -d
        if d > 0.9995:
            r = q1 + (q2 - q1) * s
        else:
            t = math.acos(max(-1.0, min(1.0, d)))
            r = (q1 * math.sin((1 - s) * t) + q2 * math.sin(s * t)) / math.sin(t)
        n = np.linalg.norm(r)
        return r / n if n > 1e-9 else q1

    @staticmethod
    def _matriz_quat(pos, q) -> np.ndarray:
        x, y, z, w = q
        r = np.array([
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ])
        return np.hstack([r, np.array(pos).reshape(3, 1)])

    @staticmethod
    def _matriz(pos, rot) -> np.ndarray:
        return Mdl._matriz_quat(pos, Mdl._quat(list(rot)))

    def vertices_pose(self, malla: dict, pose: list[np.ndarray]) -> np.ndarray:
        verts = malla["vertices"]
        huesos = malla.get("huesos")
        if huesos is None or not pose:
            return verts
        out = np.empty_like(verts)
        for i, v in enumerate(verts):
            b = huesos[i] if i < len(huesos) else 0
            m = pose[b] if b < len(pose) else pose[0]
            out[i] = m[:, :3] @ v + m[:, 3]
        return out

    def probar_animaciones(self, max_secuencias: int = 8) -> dict:
        """Evalua secuencias reales y comprueba que el esqueleto se mueve.

        Detecta lo que un parser roto no detecta: `animindex` fuera de rango,
        NaN en las poses y secuencias que deberian moverse y no lo hacen.
        """
        problemas: list[str] = []
        evaluadas = 0
        con_movimiento = 0
        estaticas = 0
        nan = 0
        for i, desc in enumerate(self.secuencias[:max_secuencias]):
            if desc["animindex"] <= 0 or desc["animindex"] >= len(self.raw):
                problemas.append(f"secuencia '{desc['nombre']}' con animindex invalido")
                continue
            frames = max(1, int(desc["cuadros"]))
            if frames <= 1:
                estaticas += 1   # las armas no se animan: 1 cuadro es normal
                continue
            poses = []
            for f in (0, frames // 3, (2 * frames) // 3, frames - 1):
                pose = self.pose(i, f)
                if any(not np.all(np.isfinite(m)) for m in pose):
                    nan += 1
                    continue
                poses.append(pose)
            evaluadas += 1
            if len(poses) >= 2:
                # se compara la posicion global de la raiz y de un hueso del pie
                raiz = poses[0][0][:, 3]
                pie = poses[0][min(20, len(poses[0]) - 1)][:, 3]
                for otra in poses[1:]:
                    if np.linalg.norm(otra[0][:, 3] - raiz) > 1e-3 or \
                       np.linalg.norm(otra[min(20, len(otra) - 1)][:, 3] - pie) > 1e-2:
                        con_movimiento += 1
                        break
        if nan:
            problemas.append(f"{nan} poses con valores no finitos")
        return {"evaluadas": evaluadas, "con_movimiento": con_movimiento,
                "estaticas": estaticas, "problemas": problemas}

    def indice_secuencia(self, nombre: str) -> int:
        for i, s in enumerate(self.secuencias):
            if s["nombre"] == nombre:
                return i
        return -1

    def validar(self) -> dict:
        problemas: list[str] = []
        if self.ident != "IDST":
            problemas.append(f"magic {self.ident!r} != 'IDST'")
        if self.version != 10:
            problemas.append(f"version {self.version} != 10")
        for h in self.huesos:
            if h["padre"] >= self.numbones:
                problemas.append(f"hueso {h['nombre']} con padre {h['padre']} inexistente")
                break
        sin_textura = sum(1 for t in self.texturas if t["rgb"] is None)
        if sin_textura:
            problemas.append(f"{sin_textura} texturas sin datos")
        sin_paleta = sum(1 for t in self.texturas if not t["paleta_incrustada"])
        if sin_paleta:
            problemas.append(f"{sin_paleta} texturas sin paleta RGB embebida")
        if not self.mallas:
            problemas.append("sin mallas legibles")
        total_tris = sum(len(m["triangulos"]) for m in self.mallas)
        return {
            "fichero": self.path.name,
            "nombre": self.nombre,
            "version": self.version,
            "huesos": self.numbones,
            "secuencias": self.numseq,
            "texturas": self.numtex,
            "mallas": len(self.mallas),
            "triangulos": total_tris,
            "problemas": problemas,
        }


def render_pose(mdl: Mdl, pose, tam: int = 300) -> Image.Image:
    """Vista frontal (X/Z, que es el plano vertical en GoldSrc) de una pose."""
    img = Image.new("RGB", (tam, tam), (14, 16, 20))
    dib = ImageDraw.Draw(img)
    mallas = [(m, mdl.vertices_pose(m, pose) if pose else mdl.vertices_modelo(m))
              for m in mdl.mallas]
    if not mallas:
        return img
    todos = np.concatenate([v for _, v in mallas])
    esc = (tam - 32) / max(np.ptp(todos[:, 0]), np.ptp(todos[:, 2]), 1e-3)
    cx = (todos[:, 0].max() + todos[:, 0].min()) / 2
    cz = (todos[:, 2].max() + todos[:, 2].min()) / 2
    for malla, pts in mallas:
        proj = [((p[0] - cx) * esc + tam / 2, (cz - p[2]) * esc + tam / 2) for p in pts]
        for (a, b, c) in malla["triangulos"]:
            if max(a, b, c) >= len(proj) or min(a, b, c) < 0:
                continue
            n = np.cross(pts[b] - pts[a], pts[c] - pts[a])
            luz = 0.55 + 0.45 * abs(n[1]) / (np.linalg.norm(n) + 1e-9)
            dib.polygon([proj[a], proj[b], proj[c]],
                        fill=(int(196 * luz), int(184 * luz), int(168 * luz)))
    return img


def render_anim(mdl: Mdl, secuencia: str, salida: Path, muestras: int = 8,
                gif: Path | None = None) -> Path | None:
    """Tira de fotogramas de una secuencia + GIF opcional."""
    idx = mdl.indice_secuencia(secuencia)
    if idx < 0:
        print(f"  (el modelo no tiene la secuencia '{secuencia}')")
        return None
    desc = mdl.secuencias[idx]
    total = max(1, int(desc["cuadros"]))
    cuadros = [round(i * (total - 1) / max(1, muestras - 1)) for i in range(muestras)]
    imgs = []
    for f in cuadros:
        im = render_pose(mdl, mdl.pose(idx, f))
        ImageDraw.Draw(im).text((6, 6), f"{secuencia}  f{f}/{total - 1}  {desc['fps']:.0f}fps",
                                fill=(120, 220, 120))
        imgs.append(im)
    cols = 4
    filas = (len(imgs) + cols - 1) // cols
    tira = Image.new("RGB", (300 * cols, 300 * filas), (10, 12, 16))
    for k, im in enumerate(imgs):
        tira.paste(im, ((k % cols) * 300, (k // cols) * 300))
    salida.parent.mkdir(parents=True, exist_ok=True)
    tira.save(salida)

    if gif is not None:
        todos = []
        for f in range(0, total, max(1, total // 24)):
            todos.append(render_pose(mdl, mdl.pose(idx, f), 200))
        if todos:
            todos[0].save(gif, save_all=True, append_images=todos[1:],
                          duration=int(1000.0 / max(1.0, desc["fps"]) * max(1, total // 24)),
                          loop=0)
    return salida


def render_modelo(mdl: Mdl, salida: Path, tam: int = 420) -> Path:
    """Vista frontal ortografica del modelo, coloreada por su textura."""
    img = Image.new("RGB", (tam, tam), (16, 18, 22))
    dib = ImageDraw.Draw(img)
    if not mdl.mallas:
        img.save(salida)
        return salida
    todos = np.concatenate([mdl.vertices_modelo(m) for m in mdl.mallas])
    escala = (tam - 40) / max(np.ptp(todos[:, 0]), np.ptp(todos[:, 2]), 1e-3)
    cx = (todos[:, 0].max() + todos[:, 0].min()) / 2
    cz = (todos[:, 2].max() + todos[:, 2].min()) / 2
    color = (196, 184, 168)
    if mdl.texturas and mdl.texturas[0]["rgb"] is not None:
        color = tuple(int(v) for v in mdl.texturas[0]["rgb"].reshape(-1, 3).mean(axis=0))
    for malla in mdl.mallas:
        pts = mdl.vertices_modelo(malla)
        proj = [((p[0] - cx) * escala + tam / 2, (cz - p[2]) * escala + tam / 2 - 10) for p in pts]
        for (a, b, c) in malla["triangulos"]:
            if max(a, b, c) >= len(proj) or min(a, b, c) < 0:
                continue
            p = [proj[a], proj[b], proj[c]]
            # sombreado plano: cuanto mira la cara al espectador (eje Z)
            n = np.cross(pts[b] - pts[a], pts[c] - pts[a])
            luz = 0.55 + 0.45 * abs(n[2]) / (np.linalg.norm(n) + 1e-9)
            dib.polygon(p, fill=tuple(int(min(255, v * luz)) for v in color),
                        outline=(20, 20, 20))
    salida.parent.mkdir(parents=True, exist_ok=True)
    img.save(salida)
    return salida


# --------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--map", help="validar/renderizar solo este mapa")
    ap.add_argument("--model", help="validar/renderizar solo este modelo")
    ap.add_argument("--no-render", action="store_true", help="no generar PNG")
    ap.add_argument("--out", default=str(SALIDA), help="carpeta de PNG")
    ap.add_argument("--anim", action="append", metavar="MODELO:SECUENCIA",
                    help="tira de fotogramas de una secuencia (repetible)")
    args = ap.parse_args()

    paleta, origen_paleta = cargar_paleta()
    print(f"paleta: {origen_paleta}")

    problemas_totales = 0

    print("\n== MAPAS ==")
    mapas = sorted(MAPS.glob("*.bsp"))
    if args.map:
        mapas = [p for p in mapas if p.stem == args.map]
    for p in mapas:
        bsp = Bsp(p, paleta)
        info = bsp.validar()
        problemas_totales += len(info["problemas"])
        estado = "ok" if not info["problemas"] else "REVISAR " + "; ".join(info["problemas"])
        print(f"  {info['fichero']:16s} {info['vertices']:>6d} vert {info['caras']:>5d} caras "
              f"{info['texturas']:>3d} tex {info['spawns']:>3d} spawns  {estado}")
        if not args.no_render:
            png = render_mapa(bsp, Path(args.out) / f"{p.stem}.png")
            print(f"      -> {png.relative_to(ROOT)}")
            mont = montaje_texturas(bsp, Path(args.out) / f"{p.stem}_texturas.png")
            if mont:
                print(f"      -> {mont.relative_to(ROOT)}")

    print("\n== MODELOS ==")
    modelos = sorted(MODELS.rglob("*.mdl"))
    if args.model:
        modelos = [p for p in modelos if p.stem == args.model]
    anim_ok = 0
    anim_total = 0
    anim_problemas = 0
    for p in modelos:
        mdl = Mdl(p, paleta)
        info = mdl.validar()
        if mdl.secuencias:
            res = mdl.probar_animaciones()
            anim_total += res["evaluadas"]
            anim_ok += res["con_movimiento"]
            anim_problemas += len(res["problemas"])
            problemas_totales += len(res["problemas"])
            info["problemas"].extend(res["problemas"])
        problemas_totales += len(info["problemas"])
        if info["problemas"]:
            print(f"  {info['fichero']:28s} {info['huesos']:>3d} huesos {info['triangulos']:>6d} tris  "
                  f"REVISAR {'; '.join(info['problemas'])}")
        elif p.stem in ("gign", "terror", "v_ak47_r", "w_ak47", "p_glock18", "hostage"):
            detalle = ""
            if mdl.secuencias:
                res = mdl.probar_animaciones()
                detalle = f" anim={res['con_movimiento']}/{res['evaluadas']}" \
                    f"{' (' + str(res['estaticas']) + ' estaticas)' if res['estaticas'] else ''}"
            print(f"  {info['fichero']:28s} {info['huesos']:>3d} huesos {info['secuencias']:>4d} seq "
                  f"{info['triangulos']:>6d} tris  ok{detalle}")
            if not args.no_render:
                png = render_modelo(mdl, Path(args.out) / f"modelo_{p.stem}.png")
                print(f"      -> {png.relative_to(ROOT)}")

    if not args.model:
        ok = sum(1 for p in modelos if not Mdl(p, paleta).validar()["problemas"])
        print(f"  {ok}/{len(modelos)} modelos sin problemas")
    if anim_total:
        print(f"  animaciones: {anim_ok}/{anim_total} secuencias evaluadas se mueven "
              f"({anim_problemas} problemas)")

    if args.anim:
        print("\n== ANIMACIONES ==")
        for espec in args.anim:
            if ":" not in espec:
                print(f"  formato incorrecto: {espec} (usa MODELO:SECUENCIA)")
                continue
            modelo, secuencia = espec.split(":", 1)
            rutas = [p for p in MODELS.rglob("*.mdl") if p.stem == modelo]
            if not rutas:
                print(f"  no encuentro el modelo '{modelo}'")
                continue
            mdl = Mdl(rutas[0], paleta)
            base = Path(args.out) / f"anim_{modelo}_{secuencia}"
            png = render_anim(mdl, secuencia, base.with_suffix(".png"), 8,
                              base.with_suffix(".gif"))
            if png:
                print(f"  {png.relative_to(ROOT)}  (+ {base.with_suffix('.gif').name})")

    print("\n== RESUMEN ==")
    print(f"  problemas de formato: {problemas_totales}")
    return 0 if problemas_totales == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
