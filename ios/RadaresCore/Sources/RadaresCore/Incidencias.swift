import Foundation

/// Tipos de incidencia de tráfico de los que se avisa.
public enum TipoIncidencia: String, Codable, CaseIterable, Sendable {
    case accidente
    case vehiculo     // vehículo detenido o averiado
    case obstaculo    // objeto u obstáculo en la calzada
    case retencion
    case meteo        // niebla, viento fuerte, mal tiempo

    /// Cómo empieza la frase: «Accidente a 2 kilómetros».
    public var nombre: String {
        switch self {
        case .accidente: return "Accidente"
        case .vehiculo: return "Vehículo detenido"
        case .obstaculo: return "Obstáculo en la calzada"
        case .retencion: return "Retención"
        case .meteo: return "Tiempo adverso"
        }
    }

    /// Horas tras las que se descarta: la DGT deja activas incidencias de hace meses.
    var horasValidez: Double {
        switch self {
        case .retencion: return 6
        case .accidente, .vehiculo: return 12
        case .obstaculo, .meteo: return 24
        }
    }
}

/// Una incidencia de tráfico en directo (DGT, DATEX II v3).
public struct Incidencia: Identifiable, Equatable, Sendable {
    public let id: String
    public let tipo: TipoIncidencia
    /// Punto donde empieza, en el sentido de la marcha.
    public let lat: Double
    public let lon: Double
    /// Sentido afectado (grados desde el norte). Sin dato = los dos.
    public let rumbo: Double?
    public let via: String?
    public let inicio: Date?

    public init(id: String, tipo: TipoIncidencia, lat: Double, lon: Double, rumbo: Double? = nil,
                via: String? = nil, inicio: Date? = nil) {
        self.id = id
        self.tipo = tipo
        self.lat = lat
        self.lon = lon
        self.rumbo = rumbo
        self.via = via
        self.inicio = inicio
    }
}

/// Lee la publicación de incidencias de la DGT
/// (`https://nap.dgt.es/datex2/v3/dgt/SituationPublication/datex2_v37.xml`).
public final class LectorIncidenciasDGT: NSObject, XMLParserDelegate {
    public static let direccion = URL(string: "https://nap.dgt.es/datex2/v3/dgt/SituationPublication/datex2_v37.xml")!

    private let ahora: Date
    private var salida: [Incidencia] = []
    private var texto = ""
    private var ruta: [String] = []
    // Registro en curso.
    private var id = ""
    private var causa = ""
    private var inicio: Date?
    private var via: String?
    private var sentido = ""
    private var desde: (Double, Double)?
    private var hasta: (Double, Double)?
    private var lat: Double?
    private var lon: Double?

    private init(ahora: Date) { self.ahora = ahora }

    /// Incidencias vigentes de los tipos que interesan. `ahora` sirve para descartar las viejas.
    public static func leer(_ datos: Data, ahora: Date = Date()) -> [Incidencia] {
        let lector = LectorIncidenciasDGT(ahora: ahora)
        let parser = XMLParser(data: datos)
        parser.shouldProcessNamespaces = false
        parser.delegate = lector
        parser.parse()
        return lector.salida
    }

    private static let fechas: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func fecha(_ s: String) -> Date? {
        if let d = fechas.date(from: s) { return d }
        let f = ISO8601DateFormatter()
        return f.date(from: s)
    }

    private static func local(_ nombre: String) -> String {
        nombre.split(separator: ":").last.map(String.init) ?? nombre
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                       qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let nombre = Self.local(elementName)
        ruta.append(nombre)
        texto = ""
        if nombre == "situationRecord" {
            id = attributes["id"] ?? UUID().uuidString
            causa = ""; inicio = nil; via = nil; sentido = ""
            desde = nil; hasta = nil
        } else if nombre == "pointCoordinates" {
            lat = nil; lon = nil
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        texto += string
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                       qualifiedName qName: String?) {
        let nombre = Self.local(elementName)
        let valor = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        texto = ""
        defer { ruta.removeLast() }

        switch nombre {
        case "causeType": causa = valor
        case "overallStartTime": inicio = Self.fecha(valor)
        case "roadName": via = valor.isEmpty ? nil : valor
        case "tpegDirection": sentido = valor
        case "latitude": lat = Double(valor)
        case "longitude": lon = Double(valor)
        case "pointCoordinates":
            guard let la = lat, let lo = lon else { break }
            // `from` / `to` son los padres de `pointCoordinates`.
            let padre = ruta.count >= 2 ? ruta[ruta.count - 2] : ""
            if padre == "from" { desde = (la, lo) } else if padre == "to" { hasta = (la, lo) }
            else if desde == nil && hasta == nil { desde = (la, lo) }
        case "situationRecord":
            terminarRegistro()
        default:
            break
        }
    }

    private func terminarRegistro() {
        let tipo: TipoIncidencia
        switch causa {
        case "accident": tipo = .accidente
        case "vehicleObstruction": tipo = .vehiculo
        case "obstruction": tipo = .obstaculo
        case "abnormalTraffic": tipo = .retencion
        case "poorEnvironment": tipo = .meteo
        default: return   // obras, gestión de carriles, etc.
        }
        if let inicio, ahora.timeIntervalSince(inicio) > tipo.horasValidez * 3600 { return }
        guard let punto = desde ?? hasta else { return }
        var rumbo: Double?
        if sentido != "unknown", sentido != "bothWays", let d = desde, let h = hasta,
           Geo.distancia(d.0, d.1, h.0, h.1) > 30 {
            rumbo = Geo.rumbo(d.0, d.1, h.0, h.1)
        }
        // Hay cientos de vehículos detenidos y casi ninguno trae el sentido: sin él avisaría
        // también de los del otro lado de la autovía.
        if tipo == .vehiculo && rumbo == nil { return }
        salida.append(Incidencia(id: id, tipo: tipo, lat: punto.0, lon: punto.1, rumbo: rumbo,
                                 via: via, inicio: inicio))
    }
}

/// Decide cuándo avisar de una incidencia: delante, en nuestro sentido y a unos 2 km.
public final class MotorIncidencias {
    /// Distancia a la que se avisa (metros).
    public var distanciaAviso = 2_000.0
    /// No se avisa por debajo de esta velocidad (m/s): en un atasco no aporta nada.
    public var velocidadMinima = 8.0

    public private(set) var incidencias: [Incidencia] = []
    private var avisadas: Set<String> = []

    public init() {}

    public func cambiar(_ nuevas: [Incidencia]) {
        incidencias = nuevas
        let vigentes = Set(nuevas.map(\.id))
        avisadas = avisadas.intersection(vigentes)
    }

    public func reiniciar() { avisadas = [] }

    public func procesar(_ p: Posicion) -> [Evento] {
        guard p.velocidad >= velocidadMinima, p.rumbo >= 0, p.precision >= 0, p.precision <= 100 else { return [] }
        var eventos: [Evento] = []
        for i in incidencias where !avisadas.contains(i.id) {
            let d = Geo.distancia(p.lat, p.lon, i.lat, i.lon)
            guard d <= distanciaAviso, d >= 150 else { continue }
            let giro = Geo.diferencia(p.rumbo, Geo.rumbo(p.lat, p.lon, i.lat, i.lon)) * .pi / 180
            guard d * cos(giro) > 0, abs(d * sin(giro)) <= max(80, 0.15 * d) else { continue }
            if let sentido = i.rumbo, abs(Geo.diferencia(p.rumbo, sentido)) > 60 { continue }
            avisadas.insert(i.id)
            eventos.append(.incidencia(i, distancia: d))
        }
        return eventos
    }
}
