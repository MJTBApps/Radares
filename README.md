# Radares (nombre provisional)

App de iPhone que avisa por voz de los radares fijos y de tramo mientras conduces, pensada para ir con el navegador y la música del propio coche (Tesla): sin mapa, sin cuentas, con el móvil bloqueado y gastando la menor batería posible.

Estado: **0.1.0, escrita y sin probar todavía en un iPhone** (14/11/2026). El núcleo está comprobado en el iMac; la app aún no se ha compilado (aquí no hay Xcode: se compila en GitHub Actions, como OpoAlert).

## Qué hace

- Lee el GPS en segundo plano y avisa unos 20 segundos antes de cada radar (entre 400 m y 1 km según la velocidad): «Radar a 650 metros. Límite 120. Vas a 131.»
- Radares de tramo: avisa al entrar, calcula la velocidad media, avisa si la media supera el límite y dice la media al salir.
- Solo avisa de lo que queda delante, en un pasillo estrecho en el sentido de la marcha, y respeta el sentido vigilado cuando la fuente lo da.
- Ahorro de batería: GPS a máxima precisión solo con un radar a menos de 10 km; se apaga solo tras 15 minutos parado.
- No avisa de radares móviles (no hay fuente abierta con su posición).

## Dónde suena el aviso

El coche suele estar con su propia música, no en la fuente Bluetooth, así que el sonido normal del iPhone no se oiría. Tres modos, a elegir en la app:

| Modo | Cómo |
|---|---|
| Altavoz del iPhone | Sale por el móvil aunque esté enlazado al coche |
| Coche, como llamada | Entra por el canal de llamadas (HFP): el coche baja la música y lo dice por sus altavoces |
| Bluetooth normal | Como una app de música: solo si el coche está en la fuente Bluetooth |

**Pendiente de probar en el coche:** cómo reacciona el Tesla al modo llamada (retraso, si enseña la pantalla de llamada) y si los tres modos suenan con el iPhone bloqueado. Los errores de sonido salen en «Últimos avisos».

Para que arranque sola: app Atajos → Automatización → «Al conectarse al Bluetooth del coche» → «Abrir app Radares» (con «Empezar al abrir la app» activado).

## Datos

`python3 scripts/actualizar_radares.py` genera `ios/Radares/Recursos/radares.json` (3.427 radares el 14/11/2026: 355 de tramo, 3.209 con límite, 2.142 con sentido).

- **OpenStreetMap** (Overpass): península, Baleares y Canarias; por la forma de la consulta entran también Portugal y la franja de frontera. Licencia ODbL: obliga a citar «© colaboradores de OpenStreetMap» y a ofrecer la base derivada con la misma licencia.
- **Servei Català de Trànsit**: 231 radares de Cataluña con carretera y límite. El archivo trae erratas en las coordenadas; el script arregla las que puede comprobar y descarta 11 filas.
- **DGT**: no incluida. Su servidor de datos devolvía error 502 el 14/11/2026 y no se pudo ver el formato.

## Carpetas

- `ios/RadaresCore/`: núcleo en Swift puro (modelos, geometría, motor de avisos, frases). `swift run RadaresChecks [radares.json]` lo comprueba con recorridos simulados.
- `ios/Radares/`: la app (SwiftUI). `Modelo.swift` (GPS y estado), `Voz.swift` (sonido), `Pantalla.swift`.
- `ios/project.yml`: proyecto de Xcode, generado con XcodeGen.
- `scripts/`: base de radares e icono.

En este iMac `swift run` falla por no tener Xcode; el núcleo se comprueba compilándolo a mano:

```bash
cd ios/RadaresCore && mkdir -p /tmp/radares && swiftc -O -parse-as-library -emit-module -emit-library -module-name RadaresCore Sources/RadaresCore/*.swift -o /tmp/radares/libRadaresCore.dylib && swiftc -O -I /tmp/radares -L /tmp/radares -lRadaresCore Sources/RadaresChecks/main.swift -o /tmp/radares/checks && (cd /tmp/radares && ./checks "$OLDPWD/../Radares/Recursos/radares.json")
```

## Compilar e instalar (GitHub Actions → TestFlight)

1. Publicar esta carpeta como repositorio en GitHub (GitHub Desktop: *Add local repository* → *Publish*). Al subirla, `ios-compilar.yml` comprueba el núcleo y que la app compila, sin secretos.
2. En el repositorio, *Settings → Secrets and variables → Actions*: los mismos tres secretos que OpoAlert (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`).
3. En App Store Connect, crear la app con el identificador `es.mjtbapps.radares`.
4. *Actions → Radares - Subir iOS a TestFlight → Run workflow*.

## Antes de publicarla

- Nombre definitivo (sin «Tesla») e icono.
- Política de privacidad (la posición no sale del iPhone).
- Texto para la revisión de Apple explicando el uso de la ubicación en segundo plano y que el permiso de micrófono no graba nada.
- Limitar la venta a los países donde estos avisadores son legales.
