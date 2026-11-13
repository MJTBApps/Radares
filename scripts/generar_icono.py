#!/usr/bin/env python3
"""Dibuja el icono de la app (1024×1024, sin transparencia) solo con la biblioteca estándar.

Fondo azul oscuro, tres ondas blancas y un punto rojo: un radar emitiendo.
    python3 scripts/generar_icono.py
"""
import math
import pathlib
import struct
import zlib

LADO = 1024
SALIDA = (pathlib.Path(__file__).resolve().parent.parent
          / "ios" / "Radares" / "Assets.xcassets" / "AppIcon.appiconset" / "icono.png")

CENTRO = (512.0, 700.0)
ONDAS = [(190.0, 30.0), (330.0, 30.0), (470.0, 30.0)]   # radio, medio grosor
APERTURA = math.radians(52)                              # a cada lado de la vertical
PUNTO = 78.0
BLANCO, ROJO = (255, 255, 255), (255, 84, 54)


def cubre(d):
    """Parte del píxel cubierta por una forma cuyo borde queda a `d` píxeles (negativo = dentro)."""
    return max(0.0, min(1.0, 0.5 - d))


def mezclar(fondo, color, a):
    return tuple(f + (c - f) * a for f, c in zip(fondo, color))


def pixel(x, y):
    t = y / (LADO - 1)
    color = (10 + 12 * t, 26 + 34 * t, 58 + 62 * t)
    dx, dy = x + 0.5 - CENTRO[0], y + 0.5 - CENTRO[1]
    r = math.hypot(dx, dy)
    if r > 1:
        angulo = abs(math.atan2(dx, -dy))                 # 0 = hacia arriba
        borde = (angulo - APERTURA) * r                   # píxeles hasta el borde del sector
        for radio, medio in ONDAS:
            a = min(cubre(abs(r - radio) - medio), cubre(borde))
            if a > 0:
                color = mezclar(color, BLANCO, a)
    a = cubre(r - PUNTO)
    if a > 0:
        color = mezclar(color, ROJO, a)
    return bytes(int(round(c)) for c in color)


def png(filas):
    def trozo(tipo, datos):
        cuerpo = tipo + datos
        return struct.pack(">I", len(datos)) + cuerpo + struct.pack(">I", zlib.crc32(cuerpo))
    cabecera = struct.pack(">IIBBBBB", LADO, LADO, 8, 2, 0, 0, 0)   # 8 bits, RGB
    return (b"\x89PNG\r\n\x1a\n" + trozo(b"IHDR", cabecera)
            + trozo(b"IDAT", zlib.compress(b"".join(b"\x00" + f for f in filas), 9)) + trozo(b"IEND", b""))


def main():
    filas = [b"".join(pixel(x, y) for x in range(LADO)) for y in range(LADO)]
    SALIDA.parent.mkdir(parents=True, exist_ok=True)
    SALIDA.write_bytes(png(filas))
    print(f"Icono escrito en {SALIDA} ({SALIDA.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
