// Comprobaciones del núcleo con recorridos simulados. En este proyecto no hay Xcode
// (ni XCTest), así que son un ejecutable: `swift run RadaresChecks [radares.json]`.
import Foundation
import RadaresCore

// `RadaresChecks --catalogo`: escribe en JSON todas las piezas de voz (para generar los audios).
if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--catalogo" {
    let lista = Frases.catalogo.map { ["clave": $0.clave, "texto": $0.texto] }
    let datos = try! JSONSerialization.data(withJSONObject: lista, options: [.prettyPrinted, .sortedKeys])
    print(String(data: datos, encoding: .utf8)!)
    exit(0)
}

var fallos = 0
func comprobar(_ ok: Bool, _ que: String) {
    print((ok ? "  bien   " : "  FALLO  ") + que)
    if !ok { fallos += 1 }
}

/// Conduce en línea recta desde `origen` con `rumbo` a `kmh`, una lectura por segundo.
func conducir(_ motor: MotorAvisos, origen: (lat: Double, lon: Double), rumbo: Double, kmh: Double,
              metros: Double, t0: Double = 0) -> [(evento: Evento, recorrido: Double)] {
    let v = kmh / 3.6
    var salida: [(Evento, Double)] = []
    var s = 0.0, t = t0
    while s <= metros {
        let p = Geo.avanzar(origen.lat, origen.lon, rumbo: rumbo, metros: s)
        let pos = Posicion(lat: p.lat, lon: p.lon, velocidad: v, rumbo: rumbo, precision: 5, instante: t)
        for e in motor.procesar(pos) { salida.append((e, s)) }
        s += v
        t += 1
    }
    return salida
}

let inicio = (lat: 41.60, lon: 1.80)

print("Geometría")
comprobar(abs(Geo.distancia(41, 2, 42, 2) - 111_195) < 50, "un grado de latitud son 111,2 km")
comprobar(abs(Geo.rumbo(41, 2, 41, 3) - 90) < 1, "hacia el este el rumbo es 90")
comprobar(Geo.diferencia(350, 10) == 20 && Geo.diferencia(10, 350) == -20, "diferencia de rumbos por el norte")
let ida = Geo.avanzar(41, 2, rumbo: 45, metros: 1000)
comprobar(abs(Geo.distancia(41, 2, ida.lat, ida.lon) - 1000) < 1, "avanzar 1000 m da 1000 m")

print("Radar fijo delante")
do {
    let p = Geo.avanzar(inicio.lat, inicio.lon, rumbo: 90, metros: 3000)
    let motor = MotorAvisos(radares: [Radar(id: "a", lat: p.lat, lon: p.lon, limite: 120)])
    let e = conducir(motor, origen: inicio, rumbo: 90, kmh: 120, metros: 6000)
    comprobar(e.count == 1, "un solo aviso (hay \(e.count))")
    if case let .radar(_, d, _)? = e.first?.evento {
        comprobar(d > 620 && d <= 667, "a 120 km/h avisa con 20 s de margen (\(Int(d)) m)")
    } else { comprobar(false, "el aviso es de radar") }
}

print("Velocidad baja y alta")
do {
    let p = Geo.avanzar(inicio.lat, inicio.lon, rumbo: 0, metros: 3000)
    let radar = Radar(id: "a", lat: p.lat, lon: p.lon, limite: 50)
    var e = conducir(MotorAvisos(radares: [radar]), origen: inicio, rumbo: 0, kmh: 40, metros: 4000)
    if case let .radar(_, d, _)? = e.first?.evento { comprobar(d > 385 && d <= 400, "a 40 km/h avisa a 400 m (\(Int(d)) m)") }
    else { comprobar(false, "avisa a 40 km/h") }
    e = conducir(MotorAvisos(radares: [radar]), origen: inicio, rumbo: 0, kmh: 200, metros: 4000)
    if case let .radar(_, d, _)? = e.first?.evento { comprobar(d > 940 && d <= 1000, "a 200 km/h avisa a 1000 m (\(Int(d)) m)") }
    else { comprobar(false, "avisa a 200 km/h") }
    e = conducir(MotorAvisos(radares: [radar]), origen: inicio, rumbo: 0, kmh: 10, metros: 4000)
    comprobar(e.isEmpty, "a 10 km/h no avisa (rumbo poco fiable)")
}

print("Radares que no tocan")
do {
    let detras = Geo.avanzar(inicio.lat, inicio.lon, rumbo: 270, metros: 300)
    let delante = Geo.avanzar(inicio.lat, inicio.lon, rumbo: 90, metros: 3000)
    let paralela = Geo.avanzar(delante.lat, delante.lon, rumbo: 0, metros: 150)
    let contrario = Radar(id: "c", lat: delante.lat, lon: delante.lon, rumbo: 270)
    comprobar(conducir(MotorAvisos(radares: [Radar(id: "d", lat: detras.lat, lon: detras.lon)]),
                       origen: inicio, rumbo: 90, kmh: 100, metros: 5000).isEmpty, "el que queda detrás no avisa")
    comprobar(conducir(MotorAvisos(radares: [Radar(id: "p", lat: paralela.lat, lon: paralela.lon)]),
                       origen: inicio, rumbo: 90, kmh: 100, metros: 5000).isEmpty, "el de una vía paralela a 150 m no avisa")
    comprobar(conducir(MotorAvisos(radares: [contrario]),
                       origen: inicio, rumbo: 90, kmh: 100, metros: 5000).isEmpty, "el del sentido contrario no avisa")
    let mismo = Radar(id: "m", lat: delante.lat, lon: delante.lon, rumbo: 80)
    comprobar(conducir(MotorAvisos(radares: [mismo]),
                       origen: inicio, rumbo: 90, kmh: 100, metros: 5000).count == 1, "el de nuestro sentido sí avisa")
}

print("Repetición")
do {
    let p = Geo.avanzar(inicio.lat, inicio.lon, rumbo: 90, metros: 2000)
    let motor = MotorAvisos(radares: [Radar(id: "a", lat: p.lat, lon: p.lon)])
    let primera = conducir(motor, origen: inicio, rumbo: 90, kmh: 90, metros: 5000)
    let segunda = conducir(motor, origen: inicio, rumbo: 90, kmh: 90, metros: 5000, t0: 1000)
    comprobar(primera.count == 1 && segunda.count == 1, "avisa una vez por pasada y otra vez al volver a pasar")
}

print("Radar de tramo")
do {
    let p = Geo.avanzar(inicio.lat, inicio.lon, rumbo: 90, metros: 2000)
    let tramo = Radar(id: "t", lat: p.lat, lon: p.lon, tipo: .tramo, limite: 100, longitud: 3000)
    var motor = MotorAvisos(radares: [tramo])
    var e = conducir(motor, origen: inicio, rumbo: 90, kmh: 95, metros: 7000)
    comprobar(e.count == 2, "sin exceso: aviso de inicio y de fin (hay \(e.count))")
    if e.count == 2, case let .finTramo(_, media) = e[1].evento {
        comprobar(media == 95, "la media es 95 (\(media))")
        comprobar(abs(e[1].recorrido - 5000) < 120, "el fin llega a los 3 km del inicio (\(Int(e[1].recorrido - 2000)) m)")
    } else { comprobar(false, "el segundo aviso es el fin del tramo") }
    comprobar(motor.tramo == nil, "al salir no queda tramo abierto")

    motor = MotorAvisos(radares: [tramo])
    e = conducir(motor, origen: inicio, rumbo: 90, kmh: 110, metros: 7000)
    comprobar(e.count == 3, "con exceso: inicio, exceso y fin (hay \(e.count))")
    if e.count == 3, case let .excesoTramo(_, media) = e[1].evento { comprobar(media == 110, "avisa de la media 110") }
    else { comprobar(false, "el segundo aviso es el exceso") }

    let fin = Geo.avanzar(p.lat, p.lon, rumbo: 90, metros: 3000)
    let conFin = Radar(id: "f", lat: p.lat, lon: p.lon, tipo: .tramo, limite: 100, finLat: fin.lat, finLon: fin.lon)
    e = conducir(MotorAvisos(radares: [conFin]), origen: inicio, rumbo: 90, kmh: 95, metros: 7000)
    comprobar(e.count == 2, "tramo con punto final: inicio y fin (hay \(e.count))")
}

print("Ahorro de batería")
do {
    let lejos = Geo.avanzar(inicio.lat, inicio.lon, rumbo: 90, metros: 14_000)
    let motor = MotorAvisos(radares: [Radar(id: "a", lat: lejos.lat, lon: lejos.lon)])
    _ = motor.procesar(Posicion(lat: inicio.lat, lon: inicio.lon, velocidad: 30, rumbo: 90, precision: 500, instante: 0))
    comprobar(!motor.necesitaPrecision, "con el radar a 14 km basta la precisión baja")
    let cerca = Geo.avanzar(inicio.lat, inicio.lon, rumbo: 90, metros: 6000)
    _ = motor.procesar(Posicion(lat: cerca.lat, lon: cerca.lon, velocidad: 30, rumbo: 90, precision: 500, instante: 200))
    comprobar(motor.necesitaPrecision, "a 8 km pide la precisión alta")
}

print("Frases")
comprobar(Frases.distancia(640) == "650 metros", "640 m se dice «650 metros»")
comprobar(Frases.distancia(1000) == "1 kilómetro", "1000 m se dice «1 kilómetro»")
comprobar(Frases.distancia(3000) == "3 kilómetros", "3000 m se dice «3 kilómetros»")
comprobar(Frases.distancia(1540) == "1,5 kilómetros", "1540 m se dice «1,5 kilómetros»")
comprobar(Frases.texto(.radar(Radar(id: "a", lat: 0, lon: 0, limite: 120), distancia: 640, velocidad: 131))
          == "Radar a 650 metros. Límite 120. Vas a 131.", "frase de radar con exceso")
comprobar(Frases.texto(.radar(Radar(id: "a", lat: 0, lon: 0, tipo: .tramo, limite: 100, longitud: 3000), distancia: 500, velocidad: 90))
          == "Radar de tramo a 500 metros. Dura 3 kilómetros. Límite 100.", "frase de tramo")

print("Piezas de voz")
do {
    let claves = Frases.catalogo.map(\.clave)
    comprobar(Set(claves).count == claves.count, "el catálogo no repite claves (\(claves.count) piezas)")
    let todas = Set(claves)
    var faltan: [String] = []
    let tramo = Radar(id: "t", lat: 0, lon: 0, tipo: .tramo, limite: 100, longitud: 7300)
    var eventos: [Evento] = [.excesoTramo(tramo, media: 113), .finTramo(tramo, media: 98)]
    for d in stride(from: 380.0, through: 1_100, by: 7) {
        eventos.append(.radar(Radar(id: "a", lat: 0, lon: 0, limite: 120), distancia: d, velocidad: 131))
        eventos.append(.radar(tramo, distancia: d, velocidad: 95))
    }
    for t in TipoIncidencia.allCases {
        for d in stride(from: 150.0, through: 2_100, by: 37) {
            eventos.append(.incidencia(Incidencia(id: "i", tipo: t, lat: 0, lon: 0), distancia: d))
        }
    }
    for e in eventos { for c in Frases.piezas(e) ?? ["sin piezas"] where !todas.contains(c) { faltan.append(c) } }
    comprobar(faltan.isEmpty, "todas las piezas de los avisos están en el catálogo \(faltan.prefix(3))")
    comprobar(Frases.piezas(.radar(Radar(id: "a", lat: 0, lon: 0, limite: 120), distancia: 640, velocidad: 131))
              == ["radar_650", "limite_120", "vas_131"], "piezas de un radar con exceso")
    comprobar(Frases.distancia(7300) == "7,5 kilómetros", "7300 m se dice «7,5 kilómetros»")
    comprobar(Frases.distancia(23_400) == "23 kilómetros", "23,4 km se dice «23 kilómetros»")
}

print("Incidencias de la DGT")
do {
    let xml = """
    <d2:payload xmlns:d2="a" xmlns:sit="b" xmlns:loc="c" xmlns:com="d">
    <sit:situation id="1"><sit:situationRecord id="r1">
      <sit:validity><com:validityTimeSpecification><com:overallStartTime>2026-11-16T10:00:00.000+01:00</com:overallStartTime></com:validityTimeSpecification></sit:validity>
      <sit:cause><sit:causeType>accident</sit:causeType></sit:cause>
      <sit:locationReference><loc:supplementaryPositionalDescription><loc:roadInformation><loc:roadName>A-7</loc:roadName></loc:roadInformation></loc:supplementaryPositionalDescription>
      <loc:tpegLinearLocation><loc:tpegDirection>northBound</loc:tpegDirection>
        <loc:to><loc:pointCoordinates><loc:latitude>41.62</loc:latitude><loc:longitude>1.80</loc:longitude></loc:pointCoordinates></loc:to>
        <loc:from><loc:pointCoordinates><loc:latitude>41.61</loc:latitude><loc:longitude>1.80</loc:longitude></loc:pointCoordinates></loc:from>
      </loc:tpegLinearLocation></sit:locationReference>
    </sit:situationRecord></sit:situation>
    <sit:situation id="2"><sit:situationRecord id="r2">
      <sit:validity><com:validityTimeSpecification><com:overallStartTime>2026-05-01T10:00:00.000+01:00</com:overallStartTime></com:validityTimeSpecification></sit:validity>
      <sit:cause><sit:causeType>accident</sit:causeType></sit:cause>
      <sit:locationReference><loc:tpegLinearLocation><loc:to><loc:pointCoordinates><loc:latitude>40</loc:latitude><loc:longitude>-3</loc:longitude></loc:pointCoordinates></loc:to></loc:tpegLinearLocation></sit:locationReference>
    </sit:situationRecord></sit:situation>
    <sit:situation id="3"><sit:situationRecord id="r3">
      <sit:cause><sit:causeType>roadMaintenance</sit:causeType></sit:cause>
      <sit:locationReference><loc:tpegLinearLocation><loc:to><loc:pointCoordinates><loc:latitude>40</loc:latitude><loc:longitude>-3</loc:longitude></loc:pointCoordinates></loc:to></loc:tpegLinearLocation></sit:locationReference>
    </sit:situationRecord></sit:situation>
    </d2:payload>
    """
    let ahora = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    let lista = LectorIncidenciasDGT.leer(Data(xml.utf8), ahora: ahora)
    comprobar(lista.count == 1, "solo queda el accidente reciente (hay \(lista.count))")
    if let i = lista.first {
        comprobar(i.tipo == .accidente && i.via == "A-7", "tipo y carretera")
        comprobar(abs(i.lat - 41.61) < 1e-9, "el punto es el inicio («from»)")
        comprobar(i.rumbo.map { abs(Geo.diferencia($0, 0)) < 1 } ?? false, "sentido hacia el norte")
    }

    let delante = Geo.avanzar(inicio.lat, inicio.lon, rumbo: 0, metros: 5_000)
    let motor = MotorIncidencias()
    motor.cambiar([Incidencia(id: "x", tipo: .retencion, lat: delante.lat, lon: delante.lon, rumbo: 0),
                   Incidencia(id: "y", tipo: .accidente, lat: delante.lat, lon: delante.lon, rumbo: 180)])
    var avisos: [(Evento, Double)] = []
    var s = 0.0
    while s < 6_000 {
        let q = Geo.avanzar(inicio.lat, inicio.lon, rumbo: 0, metros: s)
        for e in motor.procesar(Posicion(lat: q.lat, lon: q.lon, velocidad: 25, rumbo: 0, precision: 5, instante: s)) { avisos.append((e, s)) }
        s += 25
    }
    comprobar(avisos.count == 1, "avisa una vez, solo de la de nuestro sentido (hay \(avisos.count))")
    if let (e, recorrido) = avisos.first, case let .incidencia(i, d) = e {
        comprobar(i.id == "x" && d <= 2_000 && recorrido >= 2_950, "a unos 2 km (\(Int(d)) m)")
        comprobar(Frases.texto(e) == "Retención a 2 kilómetros.", "frase: \(Frases.texto(e))")
    }
}

// Con un argumento: comprobar también la base de datos real.
if CommandLine.arguments.count > 1 {
    print("Base de datos")
    do {
        let base = try BaseRadares.leer(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        comprobar(base.radares.count >= 200, "hay \(base.radares.count) radares (generado \(base.generado))")
        comprobar(Set(base.radares.map(\.id)).count == base.radares.count, "no hay identificadores repetidos")
        comprobar(base.radares.allSatisfy { (27...44.5).contains($0.lat) && (-18.5...4.6).contains($0.lon) }, "todos caen en la zona cubierta")
        comprobar(base.radares.allSatisfy { $0.limite.map { (10...130).contains($0) } ?? true }, "los límites son razonables")
        comprobar(base.radares.allSatisfy { $0.rumbo.map { (0..<360).contains($0) } ?? true }, "los rumbos van de 0 a 360")
    } catch {
        comprobar(false, "no se puede leer \(CommandLine.arguments[1]): \(error)")
    }
}

print(fallos == 0 ? "\nTodo bien." : "\n\(fallos) comprobaciones fallan.")
exit(fallos == 0 ? 0 : 1)
