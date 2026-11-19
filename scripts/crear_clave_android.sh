#!/bin/bash
# Crea la clave de subida de Chivato Radar para Google Play. Ejecutar UNA sola vez.
# Guarda la clave y su contraseña en ~/Desktop/APP/Chivato Radar (guárdalas bien: sin ellas
# no se puede actualizar la app). Copia al portapapeles lo que va en el secreto de GitHub.
set -e
DIR="$HOME/Desktop/APP/Chivato Radar"
mkdir -p "$DIR"
if [ -f "$DIR/chivato.jks" ]; then echo "Ya existe $DIR/chivato.jks; no se crea otra."; exit 1; fi
CLAVE="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
keytool -genkeypair -keystore "$DIR/chivato.jks" -alias chivato -keyalg RSA -keysize 4096 \
  -validity 10000 -storepass "$CLAVE" -keypass "$CLAVE" -dname "CN=MJTB Apps, C=ES" >/dev/null
printf '%s\n' "$CLAVE" > "$DIR/contraseña-clave.txt"
base64 -i "$DIR/chivato.jks" | pbcopy
echo "Clave creada en: $DIR"
echo
echo "1) En GitHub → Radares → Settings → Secrets and variables → Actions → New repository secret:"
echo "   Nombre: CHIVATO_KEYSTORE_B64   Valor: pega (Cmd+V), ya está copiado"
echo "2) Otro secreto: CHIVATO_KEY_PASSWORD   Valor: el contenido de contraseña-clave.txt"
open "$DIR"
