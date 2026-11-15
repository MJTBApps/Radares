#!/usr/bin/env python3
"""Dibuja el icono de la app (1024×1024, sin transparencia) solo con la biblioteca estándar.

Un bocadillo blanco sobre azul noche: dentro, un punto rojo que emite tres ondas.
Es «el chivato» que te dice dónde está el radar.
    python3 scripts/generar_icono.py [salida.png]
"""
import math
import pathlib
import struct
import sys
import zlib

LADO = 1024
SALIDA = (pathlib.Path(__file__).resolve().parent.parent
          / "ios" / "Radares" / "Assets.xcassets" / "AppIcon.appiconset" / "icono.png")

# Bocadillo: rectángulo redondeado más un pico abajo a la izquierda.
CAJA = (512.0, 446.0, 356.0, 262.0, 120.0)            # centro x, centro y, medio ancho, medio alto, radio
PICO = [(292.0, 660.0), (470.0, 660.0), (262.0, 872.0)]
REDONDEO_PICO = 16.0
# Radar: punto y ondas hacia la derecha.
PUNTO = (360.0, 446.0, 64.0)
ONDAS = [140.0, 238.0, 336.0]
GROSOR = 29.0                                           # medio grosor de cada onda
APERTURA = math.radians(36)

ROJO = (255, 78, 52)
ROJO_CLARO = (255, 138, 104)
TINTA = (17, 38, 84)


def cubre(d):
    """Parte del píxel cubierta por una forma cuyo borde queda a `d` píxeles (negativo = dentro)."""
    return max(0.0, min(1.0, 0.5 - d))


def suave(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def mezclar(fondo, color, a):
    return tuple(f + (c - f) * a for f, c in zip(fondo, color))


def d_caja(x, y):
    cx, cy, mw, mh, r = CAJA
    qx, qy = abs(x - cx) - (mw - r), abs(y - cy) - (mh - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def d_pico(x, y):
    """Distancia con signo al triángulo del pico (negativa dentro)."""
    d = float("inf")
    dentro = False
    n = len(PICO)
    for i in range(n):
        ax, ay = PICO[i]
        bx, by = PICO[(i + 1) % n]
        ex, ey = bx - ax, by - ay
        wx, wy = x - ax, y - ay
        t = max(0.0, min(1.0, (wx * ex + wy * ey) / (ex * ex + ey * ey)))
        d = min(d, math.hypot(wx - ex * t, wy - ey * t))
        if (ay > y) != (by > y) and x < ax + (y - ay) * ex / ey:
            dentro = not dentro
    return -d if dentro else d


def d_bocadillo(x, y):
    return min(d_caja(x, y), d_pico(x, y) - REDONDEO_PICO)


def d_onda(dx, dy, radio):
    """Arco con los extremos redondeados, abierto hacia la derecha."""
    angulo = abs(math.atan2(dy, dx))
    if angulo <= APERTURA:
        return abs(math.hypot(dx, dy) - radio) - GROSOR
    ex, ey = radio * math.cos(APERTURA), radio * math.sin(APERTURA)
    return math.hypot(dx - ex, abs(dy) - ey) - GROSOR


def pixel(px, py):
    x, y = px + 0.5, py + 0.5
    # Fondo: azul noche que se aclara hacia abajo, con un resplandor arriba a la izquierda.
    t = y / LADO
    color = (11 + 15 * t, 24 + 44 * t, 58 + 84 * t)
    luz = 1 - suave(0, 900, math.hypot(x - 250, y - 120))
    color = mezclar(color, (70, 120, 210), 0.30 * luz)

    # Sombra del bocadillo, desplazada hacia abajo.
    sombra = 1 - suave(-30, 70, d_bocadillo(x - 6, y - 34))
    color = mezclar(color, (4, 10, 30), 0.55 * sombra)

    d = d_bocadillo(x, y)
    a = cubre(d)
    if a > 0:
        # Blanco con un tono frío hacia abajo y un borde interior muy leve para darle volumen.
        papel = mezclar((255, 255, 255), (222, 231, 247), suave(180, 880, y))
        papel = mezclar(papel, (196, 210, 236), 0.55 * (1 - suave(0, 26, -d)) * suave(300, 760, y))
        dx, dy = x - PUNTO[0], y - PUNTO[1]
        for i, radio in enumerate(ONDAS):
            o = cubre(d_onda(dx, dy, radio))
            if o > 0:
                # Cada onda un poco más tenue que la anterior: se aleja.
                papel = mezclar(papel, TINTA, o * (1.0, 0.82, 0.62)[i])
        p = cubre(math.hypot(dx, dy) - PUNTO[2])
        if p > 0:
            brillo = 1 - suave(0, 70, math.hypot(dx + 20, dy + 22))
            papel = mezclar(papel, mezclar(ROJO, ROJO_CLARO, brillo), p)
        color = mezclar(color, papel, a)
    return bytes(max(0, min(255, int(round(c)))) for c in color)


def png(filas):
    def trozo(tipo, datos):
        cuerpo = tipo + datos
        return struct.pack(">I", len(datos)) + cuerpo + struct.pack(">I", zlib.crc32(cuerpo))
    cabecera = struct.pack(">IIBBBBB", LADO, LADO, 8, 2, 0, 0, 0)   # 8 bits, RGB
    return (b"\x89PNG\r\n\x1a\n" + trozo(b"IHDR", cabecera)
            + trozo(b"IDAT", zlib.compress(b"".join(b"\x00" + f for f in filas), 9)) + trozo(b"IEND", b""))


def main():
    salida = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else SALIDA
    filas = [b"".join(pixel(x, y) for x in range(LADO)) for y in range(LADO)]
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_bytes(png(filas))
    print(f"Icono escrito en {salida} ({salida.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
