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
                                "esc": tuple(v if v else 1.0 for v in scale[0:3])})

    def _leer_secuencias(self) -> None:
        self.secuencias = []
        for i in range(self.numseq):
            base = self.seqindex + i * 176
            if base + 176 > len(self.raw):
                break
            nombre = self.raw[base:base + 32].split(b"\0")[0].decode("latin1")
            fps, flags, frames = struct.unpack_from("<ifi", self.raw, base + 32)
            self.secuencias.append({"nombre": nombre, "fps": fps, "cuadros": frames})

    def _leer_texturas(self) -> None:
        self.texturas = []
        for i in range(self.numtex):
            base = self.textureindex + i * 80
            if base + 80 > len(self.raw):
                break
            nombre = self.raw[base:base + 64].split(b"\0")[0].decode("latin1")
            flags, w, h, idx = struct.unpack_from("<iiii", self.raw, base + 64)
            rgb = None
            if 0 < idx < len(self.raw) and w > 0 and h > 0 and w * h < 4_000_000:
                datos = self.raw[idx:idx + w * h]
                if len(datos) == w * h:
                    rgb = self.paleta[np.frombuffer(datos, dtype=np.uint8)].reshape(h, w, 3)
            self.texturas.append({"nombre": nombre, "ancho": w, "alto": h, "rgb": rgb})

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
            rx, ry, rz = h["rot"]
            cx, sx = math.cos(rx), math.sin(rx)
            cy, sy = math.cos(ry), math.sin(ry)
            cz, sz = math.cos(rz), math.sin(rz)
            # rotacion Z*Y*X (mismo orden que AngleQuaternion del motor)
            m = np.array([
                [cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx, h["pos"][0]],
                [sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx, h["pos"][1]],
                [-sy,     cy * sx,                cy * cx,                h["pos"][2]],
            ], dtype=np.float64)
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
    for p in modelos:
        mdl = Mdl(p, paleta)
        info = mdl.validar()
        problemas_totales += len(info["problemas"])
        if info["problemas"]:
            print(f"  {info['fichero']:28s} {info['huesos']:>3d} huesos {info['triangulos']:>6d} tris  "
                  f"REVISAR {'; '.join(info['problemas'])}")
        elif p.stem in ("gign", "terror", "v_ak47_r", "w_ak47", "p_glock18", "hostage"):
            print(f"  {info['fichero']:28s} {info['huesos']:>3d} huesos {info['secuencias']:>4d} seq "
                  f"{info['triangulos']:>6d} tris  ok")
            if not args.no_render:
                png = render_modelo(mdl, Path(args.out) / f"modelo_{p.stem}.png")
                print(f"      -> {png.relative_to(ROOT)}")

    if not args.model:
        ok = sum(1 for p in modelos if not Mdl(p, paleta).validar()["problemas"])
        print(f"  {ok}/{len(modelos)} modelos sin problemas")

    print("\n== RESUMEN ==")
    print(f"  problemas de formato: {problemas_totales}")
    return 0 if problemas_totales == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
