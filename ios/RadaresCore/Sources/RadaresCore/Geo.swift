import Foundation

public enum Geo {
    static let radioTierra = 6_371_000.0

    /// Distancia en metros entre dos puntos.
    public static func distancia(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let f1 = lat1 * .pi / 180, f2 = lat2 * .pi / 180
        let df = f2 - f1, dl = (lon2 - lon1) * .pi / 180
        let a = sin(df / 2) * sin(df / 2) + cos(f1) * cos(f2) * sin(dl / 2) * sin(dl / 2)
        return 2 * radioTierra * asin(min(1, sqrt(a)))
    }

    /// Rumbo inicial (0–360, desde el norte) para ir del primer punto al segundo.
    public static func rumbo(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let f1 = lat1 * .pi / 180, f2 = lat2 * .pi / 180
        let dl = (lon2 - lon1) * .pi / 180
        let y = sin(dl) * cos(f2)
        let x = cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dl)
        let g = atan2(y, x) * 180 / .pi
        return g < 0 ? g + 360 : g
    }

    /// Diferencia entre dos rumbos, de -180 a 180.
    public static func diferencia(_ a: Double, _ b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// Punto a `metros` del origen siguiendo `rumbo` (para las comprobaciones).
    public static func avanzar(_ lat: Double, _ lon: Double, rumbo: Double, metros: Double) -> (lat: Double, lon: Double) {
        let d = metros / radioTierra, r = rumbo * .pi / 180
        let f1 = lat * .pi / 180, l1 = lon * .pi / 180
        let f2 = asin(sin(f1) * cos(d) + cos(f1) * sin(d) * cos(r))
        let l2 = l1 + atan2(sin(r) * sin(d) * cos(f1), cos(d) - sin(f1) * sin(f2))
        return (f2 * 180 / .pi, l2 * 180 / .pi)
    }
}

/// Radares repartidos en una rejilla para no recorrer toda la lista en cada lectura del GPS.
public struct IndiceRadares: Sendable {
    public let radares: [Radar]
    private let celdas: [Int64: [Int32]]
    private static let paso = 0.05   // grados: unos 5,5 km de alto

    public init(_ radares: [Radar]) {
        self.radares = radares
        var c: [Int64: [Int32]] = [:]
        for (i, r) in radares.enumerated() {
            c[Self.clave(Self.fila(r.lat), Self.fila(r.lon)), default: []].append(Int32(i))
        }
        celdas = c
    }

    private static func fila(_ grados: Double) -> Int { Int((grados / paso).rounded(.down)) }
    private static func clave(_ a: Int, _ b: Int) -> Int64 { Int64(a) * 100_000 + Int64(b) }

    /// Radares a menos de `radio` metros, del más cercano al más lejano.
    public func cercanos(lat: Double, lon: Double, radio: Double) -> [(radar: Radar, distancia: Double)] {
        let dLat = radio / 111_000
        let dLon = radio / (111_000 * max(0.2, cos(lat * .pi / 180)))
        var salida: [(radar: Radar, distancia: Double)] = []
        for a in Self.fila(lat - dLat)...Self.fila(lat + dLat) {
            for b in Self.fila(lon - dLon)...Self.fila(lon + dLon) {
                guard let lista = celdas[Self.clave(a, b)] else { continue }
                for i in lista {
                    let r = radares[Int(i)]
                    let d = Geo.distancia(lat, lon, r.lat, r.lon)
                    if d <= radio { salida.append((r, d)) }
                }
            }
        }
        return salida.sorted { $0.distancia < $1.distancia }
    }

    /// Distancia al radar más cercano, o nil si no hay ninguno a menos de `tope` metros.
    public func distanciaAlMasCercano(lat: Double, lon: Double, tope: Double) -> Double? {
        cercanos(lat: lat, lon: lon, radio: tope).first?.distancia
    }
}
