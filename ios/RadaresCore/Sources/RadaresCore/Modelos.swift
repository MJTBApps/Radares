import Foundation

public enum TipoRadar: String, Codable, Sendable {
    case fijo
    case tramo
}

/// Un radar de la base de datos (`radares.json`, generado por `scripts/actualizar_radares.py`).
public struct Radar: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let lat: Double
    public let lon: Double
    public let tipo: TipoRadar
    /// Límite en km/h, si la fuente lo da.
    public let limite: Int?
    /// Carretera («A-2»), si la fuente la da.
    public let via: String?
    /// Sentido de circulación que vigila, en grados desde el norte. Sin dato = cualquier sentido.
    public let rumbo: Double?
    /// Final del tramo (solo radares de tramo), si se conoce el punto.
    public let finLat: Double?
    public let finLon: Double?
    /// Longitud del tramo en metros, si se conoce.
    public let longitud: Double?
    public let fuente: String

    public init(id: String, lat: Double, lon: Double, tipo: TipoRadar = .fijo, limite: Int? = nil,
                via: String? = nil, rumbo: Double? = nil, finLat: Double? = nil, finLon: Double? = nil,
                longitud: Double? = nil, fuente: String = "") {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.tipo = tipo
        self.limite = limite
        self.via = via
        self.rumbo = rumbo
        self.finLat = finLat
        self.finLon = finLon
        self.longitud = longitud
        self.fuente = fuente
    }
}

/// Contenido completo de `radares.json`.
public struct BaseRadares: Codable, Sendable {
    /// Fecha de generación (AAAA-MM-DD).
    public let generado: String
    /// Radares aportados por cada fuente.
    public let fuentes: [String: Int]
    public let radares: [Radar]

    public init(generado: String, fuentes: [String: Int], radares: [Radar]) {
        self.generado = generado
        self.fuentes = fuentes
        self.radares = radares
    }

    public static func leer(_ datos: Data) throws -> BaseRadares {
        try JSONDecoder().decode(BaseRadares.self, from: datos)
    }
}

/// Una lectura del GPS.
public struct Posicion: Equatable, Sendable {
    public let lat: Double
    public let lon: Double
    /// m/s; negativo = desconocida.
    public let velocidad: Double
    /// Grados desde el norte; negativo = desconocido.
    public let rumbo: Double
    /// Error horizontal en metros.
    public let precision: Double
    /// Segundos (reloj absoluto).
    public let instante: TimeInterval

    public init(lat: Double, lon: Double, velocidad: Double, rumbo: Double, precision: Double, instante: TimeInterval) {
        self.lat = lat
        self.lon = lon
        self.velocidad = velocidad
        self.rumbo = rumbo
        self.precision = precision
        self.instante = instante
    }

    public var kmh: Int { velocidad < 0 ? 0 : Int((velocidad * 3.6).rounded()) }
}
