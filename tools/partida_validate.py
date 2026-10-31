#!/usr/bin/env python3
"""Comprueba el modo de juego sin Godot.

Dos cosas, y ninguna necesita el motor:

1. **Constantes**: se leen del propio GDScript (`economy.gd`,
   `match_director.gd`, `bomb.gd`) y se contrastan con los valores del manual de
   CS 1.5. Si alguien toca un número por accidente, salta aquí.
2. **Economía**: se simulan partidas (rachas de derrotas, victorias, bajas de
   cuchillo y AWP) con las mismas reglas que `match_director.gd` y se comprueba
   que el dinero nunca baja de 0 ni pasa de 16000 y que el bono de derrota sube
   como en el original.

No sustituye a ejecutar el juego: valida los números y la aritmética, no que
Godot arranque.

Uso: python3 tools/partida_validate.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"


def leer_constantes(fichero: str) -> dict[str, object]:
    """Extrae `const NOMBRE := valor` / `const NOMBRE = valor` de un script."""
    texto = (SCRIPTS / fichero).read_text(encoding="utf-8")
    salida: dict[str, object] = {}
    for nombre, valor in re.findall(
            r"^const\s+([A-Z_][A-Z0-9_]*)\s*:?=\s*([0-9.]+|\[[^\]]*\])\s*(?:#.*)?$",
            texto, re.MULTILINE):
        valor = valor.strip()
        if valor.startswith("["):
            salida[nombre] = [int(float(v)) for v in re.findall(r"[0-9.]+", valor)]
        else:
            salida[nombre] = float(valor) if "." in valor else int(valor)
    return salida


# --- valores del manual de CS 1.5 -------------------------------------------

ECONOMIA_ESPERADA = {
    "DINERO_INICIAL": 800,
    "DINERO_MAX": 16000,
    "VICTORIA_ELIMINACION": 3250,
    "VICTORIA_BOMBA_EXPLOTA": 3500,
    "VICTORIA_BOMBA_DESACTIVADA": 3500,
    "VICTORIA_TIEMPO": 3250,
    "VICTORIA_REHENES": 2000,
    "BAJA": 300,
    "BAJA_CUCHILLO": 1500,
    "BAJA_AWP": 150,
    "PLANTAR_BOMBA": 300,
    "DESACTIVAR_BOMBA": 300,
    "MULTA_TEAMKILL": 3300,
    "MULTA_SUICIDIO": 3300,
}
BONO_DERROTA_ESPERADO = [1400, 1900, 2400, 2900]
TIEMPOS_ESPERADOS = {
    "match_director.gd": {
        "TIEMPO_CONGELACION": 6,
        "TIEMPO_RONDA": 300,      # mp_roundtime 5
        "TIEMPO_FIN_RONDA": 5,    # mp_chattime
        "TIEMPO_PLANTAR": 3,
    },
    "bomb.gd": {
        "TIEMPO": 35,             # mp_c4timer del 1.5 (40 en el 1.6)
    },
}
PRECIOS_ESPERADOS = {
    # del menú de compra del 1.5, los más característicos
    "glock18": 400, "usp45": 500, "deagle": 650, "awp": 4750,
    "ak47": 2500, "m4a1": 3100, "m3": 1700, "mp5": 1500,
    "hegrenade": 300, "flashbang": 200, "smokegrenade": 300,
    "kevlar": 650, "kevlar_casco": 1000, "kit": 200,
}


def comprobar_constantes(problemas: list[str]) -> None:
    eco = leer_constantes("economy.gd")
    for nombre, esperado in ECONOMIA_ESPERADA.items():
        real = eco.get(nombre)
        if real != esperado:
            problemas.append(f"economy.gd: {nombre} = {real}, se esperaba {esperado}")
    if eco.get("BONO_DERROTA") != BONO_DERROTA_ESPERADO:
        problemas.append(f"economy.gd: BONO_DERROTA = {eco.get('BONO_DERROTA')}, "
                         f"se esperaba {BONO_DERROTA_ESPERADO}")
    for fichero, esperados in TIEMPOS_ESPERADOS.items():
        reales = leer_constantes(fichero)
        for nombre, esperado in esperados.items():
            real = reales.get(nombre)
            if real != esperado:
                problemas.append(f"{fichero}: {nombre} = {real}, se esperaba {esperado}")


def comprobar_precios(problemas: list[str]) -> None:
    """Los precios del menú de compra salen de `weapon_db.gd` y `economy.gd`."""
    armas = (SCRIPTS / "weapon_db.gd").read_text(encoding="utf-8")
    precios: dict[str, int] = {}
    # Cada arma empieza en `\t"id": {` y la ficha sigue hasta la siguiente.
    entradas = list(re.finditer(r'^\t"([a-z0-9_]+)":\s*\{', armas, re.MULTILINE))
    for i, entrada in enumerate(entradas):
        fin = entradas[i + 1].start() if i + 1 < len(entradas) else len(armas)
        m = re.search(r'"precio":\s*(\d+)', armas[entrada.end():fin])
        if m:
            precios[entrada.group(1)] = int(m.group(1))
    equipo = (SCRIPTS / "economy.gd").read_text(encoding="utf-8")
    for nombre, precio in re.findall(r'^\t"([a-z0-9_]+)":\s*\{"nombre":\s*"[^"]+",\s*"precio":\s*(\d+)',
                                     equipo, re.M):
        precios.setdefault(nombre, int(precio))

    for arma, esperado in PRECIOS_ESPERADOS.items():
        real = precios.get(arma)
        if real != esperado:
            problemas.append(f"precio de {arma} = {real}, se esperaba {esperado}")

    # todo lo que el menú ofrece debe tener precio > 0
    menu = re.search(r"static func categorias\(\).*?return \[(.*?)\n\t\]",
                     equipo, re.S).group(1)
    for objeto in set(re.findall(r'"([a-z0-9_]+)"', " ".join(
            re.findall(r'"objetos": \[(.*?)\]', menu)))):
        if precios.get(objeto, 0) <= 0:
            problemas.append(f"el menú ofrece '{objeto}' y no tiene precio")


# --- simulación de la economía ----------------------------------------------

class Economia:
    """Misma aritmética que `economy.gd` + `match_director.gd`."""

    def __init__(self, inicial: int, tope: int, bonos: list[int]) -> None:
        self.dinero = inicial
        self.tope = tope
        self.bonos = bonos
        self.derrotas_seguidas = 0

    def pagar(self, cantidad: int) -> None:
        self.dinero = max(0, min(self.tope, self.dinero + cantidad))

    def bono_derrota(self) -> int:
        return self.bonos[min(self.derrotas_seguidas, len(self.bonos) - 1)]

    def fin_de_ronda(self, gana: bool, recompensa: int) -> None:
        if gana:
            self.pagar(recompensa)
            self.derrotas_seguidas = 0
        else:
            self.pagar(self.bono_derrota())
            self.derrotas_seguidas += 1


def comprobar_economia(problemas: list[str]) -> int:
    eco = leer_constantes("economy.gd")
    sim = Economia(eco["DINERO_INICIAL"], eco["DINERO_MAX"], eco["BONO_DERROTA"])

    # 1) cuatro derrotas seguidas: el bono tiene que subir y luego estabilizarse
    vistos = []
    for _ in range(6):
        sim.fin_de_ronda(False, 0)
        vistos.append(sim.bono_derrota())
    if vistos != [1900, 2400, 2900, 2900, 2900, 2900]:
        problemas.append(f"el bono de derrota evoluciona mal: {vistos}")

    # 2) una victoria corta la racha
    sim.fin_de_ronda(True, eco["VICTORIA_ELIMINACION"])
    if sim.derrotas_seguidas != 0:
        problemas.append("ganar no reinicia la racha de derrotas")

    # 3) el dinero nunca se sale de los límites en una partida larga
    sim2 = Economia(eco["DINERO_INICIAL"], eco["DINERO_MAX"], eco["BONO_DERROTA"])
    for ronda in range(200):
        gana = ronda % 3 == 0
        sim2.pagar(eco["BAJA"] if ronda % 2 else eco["BAJA_CUCHILLO"])
        sim2.fin_de_ronda(gana, eco["VICTORIA_BOMBA_EXPLOTA"])
        if not 0 <= sim2.dinero <= eco["DINERO_MAX"]:
            problemas.append(f"dinero fuera de rango en la ronda {ronda}: {sim2.dinero}")
            break

    # 4) con derrotas eternas y sin gastar, el tope se alcanza pero no se pasa
    sim3 = Economia(eco["DINERO_MAX"] - 100, eco["DINERO_MAX"], eco["BONO_DERROTA"])
    sim3.fin_de_ronda(False, 0)
    if sim3.dinero != eco["DINERO_MAX"]:
        problemas.append(f"el tope de dinero no se respeta: {sim3.dinero}")

    # 5) sin dinero no se puede bajar de cero (multas de teamkill)
    sim4 = Economia(100, eco["DINERO_MAX"], eco["BONO_DERROTA"])
    sim4.pagar(-eco["MULTA_TEAMKILL"])
    if sim4.dinero != 0:
        problemas.append(f"una multa deja el dinero negativo: {sim4.dinero}")

    return 200


def comprobar_tiempos_de_ronda(problemas: list[str]) -> None:
    """La ronda completa tiene que caber en los tiempos del 1.5."""
    dirs = leer_constantes("match_director.gd")
    bomb = leer_constantes("bomb.gd")
    # la C4 tiene que poder desactivarse antes de explotar, con y sin kit
    if bomb["TIEMPO"] <= 10.0:
        problemas.append("la C4 explota antes de que se pueda desactivar sin kit")
    # y la ronda tiene que durar más que la congelación
    if dirs["TIEMPO_RONDA"] <= dirs["TIEMPO_CONGELACION"]:
        problemas.append("la ronda dura menos que la congelación")
    # plantar tiene que ser posible en una ronda
    if dirs["TIEMPO_PLANTAR"] >= dirs["TIEMPO_RONDA"]:
        problemas.append("plantar la bomba no cabe en una ronda")


def main() -> int:
    problemas: list[str] = []
    comprobar_constantes(problemas)
    comprobar_precios(problemas)
    rondas = comprobar_economia(problemas)
    comprobar_tiempos_de_ronda(problemas)

    print("== MODO DE JUEGO ==")
    print(f"  constantes y precios del 1.5 contrastados")
    print(f"  economica simulada en {rondas} rondas sin salirse de [0, 16000]")
    if problemas:
        print(f"\n  problemas: {len(problemas)}")
        for p in problemas:
            print("   -", p)
        return 1
    print("  problemas: 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
