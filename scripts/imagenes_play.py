"""Icono 512x512 y grafico destacado 1024x500 para la ficha de Google Play.

Uso: python3 imagenes_play.py <icono_1024.png> <carpeta_salida>
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

icono = Image.open(sys.argv[1]).convert("RGBA")
salida = Path(sys.argv[2])
salida.mkdir(parents=True, exist_ok=True)

icono.resize((512, 512), Image.LANCZOS).convert("RGB").save(salida / "icono-512.png")

azul = (27, 77, 177)
g = Image.new("RGB", (1024, 500), azul)
d = ImageDraw.Draw(g)
# Degradado suave hacia abajo.
for y in range(500):
    t = y / 499
    d.line([(0, y), (1024, y)], fill=tuple(int(c * (1 - 0.35 * t)) for c in azul))

lado = 300
mask = Image.new("L", (lado, lado), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, lado, lado], radius=66, fill=255)
g.paste(icono.resize((lado, lado), Image.LANCZOS), (70, 100), mask)


def fuente(tam, negrita):
    for nombre in (["DejaVuSans-Bold.ttf"] if negrita else ["DejaVuSans.ttf"]):
        for base in ("/usr/share/fonts/truetype/dejavu/", ""):
            try:
                return ImageFont.truetype(base + nombre, tam)
            except OSError:
                pass
    return ImageFont.load_default()


d.text((420, 150), "Chivato Radar", font=fuente(66, True), fill="white")
lineas = ["Avisos por voz de radares", "fijos y de tramo, también por", "los altavoces del coche."]
for i, l in enumerate(lineas):
    d.text((424, 250 + i * 46), l, font=fuente(34, False), fill=(225, 233, 250))
g.save(salida / "grafico-destacado-1024x500.png")
print("Hecho:", sorted(p.name for p in salida.iterdir()))
