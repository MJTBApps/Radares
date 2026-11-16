#!/usr/bin/env python3
"""Genera los audios de las voces naturales con la API de voz de OpenAI.

Cada aviso se dice encadenando frases cortas («Radar a 650 metros.», «Límite 120.»).
La lista completa sale del núcleo de la app (`RadaresChecks --catalogo`) y está en
`scripts/catalogo_voces.json`; si se cambian las frases hay que regenerarla.

La clave de la API NO va en el repositorio: se lee de la variable OPENAI_API_KEY o del
archivo ~/Radares-claves/openai.txt.

    python3 scripts/generar_voces.py --voz lucia --openai-voz coral
    python3 scripts/generar_voces.py --voz pablo --openai-voz ash --solo 20   # prueba con 20

Escribe ios/Radares/Voces/<voz>/<clave>.mp3 y no repite los que ya existen.
Las voces de OpenAI son sintéticas: Apple y OpenAI piden decir al usuario que son voces
generadas por IA (la app lo indica junto al selector de voz).
"""
import argparse
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

RAIZ = pathlib.Path(__file__).resolve().parent.parent
CATALOGO = RAIZ / "scripts" / "catalogo_voces.json"
VOCES = RAIZ / "ios" / "Radares" / "Voces"
API = "https://api.openai.com/v1/audio/speech"

INSTRUCCIONES = (
    "Habla en español de España, con acento peninsular neutro. Eres el copiloto de un coche: "
    "tono tranquilo, claro y cercano, ritmo ágil pero sin prisa, como quien avisa a un amigo "
    "que conduce. Pronuncia los números completos. Sin pausas al principio ni al final."
)


def clave_api():
    if os.environ.get("OPENAI_API_KEY"):
        return os.environ["OPENAI_API_KEY"].strip()
    archivo = pathlib.Path.home() / "Radares-claves" / "openai.txt"
    if archivo.exists():
        return archivo.read_text().strip()
    sys.exit("Falta la clave: crea ~/Radares-claves/openai.txt o define OPENAI_API_KEY.")


def generar(texto, voz, modelo, clave):
    cuerpo = json.dumps({
        "model": modelo, "voice": voz, "input": texto,
        "instructions": INSTRUCCIONES, "response_format": "mp3",
    }).encode()
    pet = urllib.request.Request(API, data=cuerpo, headers={
        "Authorization": f"Bearer {clave}", "Content-Type": "application/json"})
    for intento in range(5):
        try:
            with urllib.request.urlopen(pet, timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503) and intento < 4:
                time.sleep(2 ** intento * 3)
                continue
            sys.exit(f"Error {e.code} de OpenAI con «{texto}»: {e.read()[:300]!r}")
        except urllib.error.URLError:
            time.sleep(5)
    sys.exit(f"No se ha podido generar «{texto}»")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--voz", required=True, help="nombre en la app (carpeta), p. ej. lucia")
    p.add_argument("--openai-voz", required=True, help="voz de OpenAI: alloy, ash, coral, sage, nova…")
    p.add_argument("--modelo", default="gpt-4o-mini-tts")
    p.add_argument("--solo", type=int, help="generar solo las N primeras (para probar)")
    a = p.parse_args()

    catalogo = json.loads(CATALOGO.read_text())
    if a.solo:
        catalogo = catalogo[: a.solo]
    destino = VOCES / a.voz
    destino.mkdir(parents=True, exist_ok=True)
    clave = clave_api()
    hechos = 0
    for i, pieza in enumerate(catalogo, 1):
        archivo = destino / f"{pieza['clave']}.mp3"
        if archivo.exists() and archivo.stat().st_size > 0:
            continue
        archivo.write_bytes(generar(pieza["texto"], a.openai_voz, a.modelo, clave))
        hechos += 1
        if hechos % 50 == 0:
            print(f"{i}/{len(catalogo)}…", flush=True)
    total = sum(f.stat().st_size for f in destino.glob("*.mp3"))
    print(f"Voz «{a.voz}»: {hechos} audios nuevos, {len(list(destino.glob('*.mp3')))} en total, "
          f"{total // 1024 // 1024} MB")


if __name__ == "__main__":
    main()
