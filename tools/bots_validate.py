#!/usr/bin/env python3
"""Comprueba el equilibrio de los bots sin Godot.

La IA de `scripts/bot_ai.gd` dispara rayos con un error angular que depende de
la dificultad, la distancia y la dispersión del arma, y dispara a ráfagas. Ese
modelo es aritmética pura, así que se puede replicar aquí y responder preguntas
que de otro modo solo se contestarían jugando:

* ¿Cuántos disparos aciertan a 5, 10, 20 y 30 m?
* ¿Cuánto tarda un bot en matar (100 de vida)?
* ¿Le da tiempo a matar antes de quedarse sin cargador?

Los límites (`LIMITES`) son de sentido común, no del original: están para
detectar una IA que sea una máquina de precisión o un manco absoluto.

Uso: python3 tools/bots_validate.py
"""
from __future__ import annotations

import math
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"

# Hitbox del jugador: cápsula de 32 u de diámetro -> 0.4 m de radio efectivo.
RADIO_JUGADOR = 0.32
ALTURA_JUGADOR = 1.8
VIDA_JUGADOR = 100
DISTANCIAS = (5.0, 10.0, 20.0, 30.0)
MUESTRAS = 20000

LIMITES = {
    # dificultad: (aciertos/s mínimo, aciertos/s máximo) a 10 m
    "fácil": (1.2, 4.0),
    "normal": (2.0, 6.5),
    "difícil": (2.8, 9.0),
}


def niveles_de_bot() -> list[dict]:
    """Extrae la tabla NIVELES de bot_ai.gd."""
    texto = (SCRIPTS / "bot_ai.gd").read_text(encoding="utf-8")
    bloque = re.search(r"const NIVELES := \[(.*?)\n\]", texto, re.S).group(1)
    niveles = []
    for linea in re.findall(r"\{(.*?)\}", bloque, re.S):
        limpio = {}
        for clave, texto_v, numero in re.findall(
                r'"(\w+)":\s*(?:"([^"]*)"|([0-9.]+))', linea):
            limpio[clave] = texto_v if texto_v else float(numero)
        limpio["nombre"] = str(limpio["nombre"])
        niveles.append(limpio)
    return niveles


def armas_de_bot() -> dict[str, dict]:
    texto = (SCRIPTS / "weapon_db.gd").read_text(encoding="utf-8")
    entradas = list(re.finditer(r'^\t"([a-z0-9_]+)":\s*\{', texto, re.MULTILINE))
    salida = {}
    for i, entrada in enumerate(entradas):
        fin = entradas[i + 1].start() if i + 1 < len(entradas) else len(texto)
        trozo = texto[entrada.end():fin]
        datos = {}
        for campo in ("danio", "cadencia", "dispersion", "cargador", "reserva"):
            m = re.search(r'"%s":\s*([0-9.]+)' % campo, trozo)
            if m:
                datos[campo] = float(m.group(1))
        salida[entrada.group(1)] = datos
    return salida


def simular(nivel: dict, arma: dict, distancia: float, rng: random.Random,
            indice: int = 1) -> dict:
    """Dispara ráfagas como `_disparar()` y cuenta aciertos."""
    cadencia = arma["cadencia"]
    rafaga = 0
    espera = 0.0
    tiempo = 0.0
    disparos = 0
    aciertos = 0
    danio = 0.0
    cargador = int(arma.get("cargador", 30))
    tiempo_matar = None

    while disparos < MUESTRAS:
        if espera > 0.0:
            tiempo += espera
            espera = 0.0
            continue
        if cargador <= 0:
            tiempo += 2.4       # recarga
            cargador = int(arma.get("cargador", 30))
            continue

        cargador -= 1
        disparos += 1
        # el modelo de bot_ai.gd, línea por línea
        error_grados = nivel["error"] * (0.6 + distancia / 25.0) * (0.5 + arma["dispersion"] * 0.5)
        sigma = math.tan(math.radians(error_grados)) * 0.5
        dx = rng.gauss(0.0, sigma) * distancia
        dy = rng.gauss(0.0, sigma) * distancia
        if abs(dx) <= RADIO_JUGADOR and abs(dy) <= ALTURA_JUGADOR * 0.5:
            aciertos += 1
            danio += arma["danio"]
            if tiempo_matar is None and danio >= VIDA_JUGADOR:
                tiempo_matar = tiempo

        espera = 60.0 / max(1.0, float(nivel["cadencia"]) * cadencia)
        rafaga -= 1
        if rafaga <= 0:
            rafaga = rng.randint(3, 6)
            espera += rng.uniform(0.35, 1.1) * (1.3 - 0.25 * indice)

    return {
        "aciertos": aciertos / disparos,
        "aciertos_s": aciertos / tiempo if tiempo > 0 else 0.0,
        "danio_s": danio / tiempo if tiempo > 0 else 0.0,
        "ttk": tiempo_matar,
    }


def main() -> int:
    niveles = niveles_de_bot()
    armas = armas_de_bot()
    arma = armas.get("ak47")
    if not niveles or not arma:
        print("no se han podido leer NIVELES o el ak47")
        return 1

    problemas: list[str] = []
    rng = random.Random(1234)

    print(f"arma: ak47  daño {arma['danio']:.0f}  cadencia {arma['cadencia']:.0f}  "
          f"dispersión {arma['dispersion']:.2f}  cargador {arma['cargador']:.0f}")
    print(f"jugador: {VIDA_JUGADOR} de vida, radio {RADIO_JUGADOR:.2f} m\n")
    print(f"{'dificultad':10} {'dist':>5} {'aciertos':>9} {'ac/s':>6} {'daño/s':>7} {'TTK':>7}")

    for indice, nivel in enumerate(niveles):
        for distancia in DISTANCIAS:
            r = simular(nivel, arma, distancia, rng, indice)
            ttk = f"{r['ttk']:.2f}s" if r["ttk"] is not None else "  —"
            print(f"{nivel['nombre']:10} {distancia:5.0f} {r['aciertos'] * 100:8.1f}% "
                  f"{r['aciertos_s']:6.1f} {r['danio_s']:7.0f} {ttk:>7}")
        # comprobaciones de cordura
        cerca = simular(nivel, arma, 10.0, rng, indice)
        lejos = simular(nivel, arma, 30.0, rng, indice)
        minimo, maximo = LIMITES[nivel["nombre"]]
        if not minimo <= cerca["aciertos_s"] <= maximo:
            problemas.append(f"{nivel['nombre']}: {cerca['aciertos_s']:.1f} aciertos/s a 10 m "
                             f"fuera de [{minimo}, {maximo}]")
        if lejos["aciertos_s"] >= cerca["aciertos_s"]:
            problemas.append(f"{nivel['nombre']}: acierta igual o más de lejos que de cerca")
        if cerca["ttk"] is None:
            problemas.append(f"{nivel['nombre']}: no mata a 10 m ni vaciando el cargador")
        elif cerca["ttk"] > 4.0:
            problemas.append(f"{nivel['nombre']}: tarda {cerca['ttk']:.1f} s en matar a 10 m")
        print()

    # El difícil tiene que ser mejor que el fácil en el mismo escenario.
    if len(niveles) >= 2:
        facil = simular(niveles[0], arma, 20.0, rng, 0)["aciertos_s"]
        dificil = simular(niveles[-1], arma, 20.0, rng, len(niveles) - 1)["aciertos_s"]
        if dificil <= facil:
            problemas.append("el nivel difícil no acierta más que el fácil")

    if problemas:
        print(f"problemas: {len(problemas)}")
        for p in problemas:
            print("  -", p)
        return 1
    print("problemas: 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
