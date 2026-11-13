import Foundation

public struct AjustesMotor: Sendable {
    /// Segundos de margen con los que se quiere oír el aviso.
    public var segundosAntelacion = 20.0
    /// El aviso nunca se da a menos ni a más distancia que estas (metros).
    public var distanciaMinima = 400.0
    public var distanciaMaxima = 1000.0
    /// Por debajo de esta velocidad (m/s) el rumbo del GPS no es fiable: no se avisa.
    public var velocidadMinima = 4.0
    /// Un radar avisado no se repite hasta alejarse esta distancia (metros).
    public var rearme = 1500.0
    /// Con un error del GPS mayor que este (metros) no se avisa.
    public var precisionMaxima = 100.0
    /// Media de tramo por encima del límite (km/h) a partir de la cual se avisa.
    public var margenTramo = 2

    public init() {}
}

public enum Evento: Equatable, Sendable {
    /// Radar delante. `velocidad` es la del coche en km/h en ese momento.
    case radar(Radar, distancia: Double, velocidad: Int)
    /// Dentro de un tramo, la media supera el límite.
    case excesoTramo(Radar, media: Int)
    /// Fin del tramo, con la media conseguida.
    case finTramo(Radar, media: Int)
}

/// Seguimiento de un radar de tramo desde que se avisa hasta que se sale.
public struct EstadoTramo: Equatable, Sendable {
    public let radar: Radar
    /// false = todavía acercándose al inicio.
    public internal(set) var dentro = false
    public internal(set) var recorrido = 0.0
    public internal(set) var tiempo = 0.0
    var menorDistancia = Double.greatestFiniteMagnitude
    var ultima: Posicion?
    var excesoAvisado = false

    /// Media en km/h desde el inicio del tramo.
    public var media: Int? {
        guard dentro, tiempo >= 5, recorrido >= 100 else { return nil }
        return Int((recorrido / tiempo * 3.6).rounded())
    }

    /// Metros que quedan, si se conoce la longitud.
    public var restante: Double? {
        guard dentro, let largo = radar.longitud else { return nil }
        return max(0, largo - recorrido)
    }
}

/// Decide cuándo avisar. Recibe cada lectura del GPS y devuelve lo que hay que decir.
public final class MotorAvisos {
    public var ajustes: AjustesMotor
    public private(set) var indice: IndiceRadares

    /// Radar más cercano de los que están delante (para la pantalla).
    public private(set) var proximo: (radar: Radar, distancia: Double)?
    public private(set) var tramo: EstadoTramo?
    /// Distancia al radar más cercano en cualquier dirección (hasta 15 km).
    public private(set) var distanciaMasCercano: Double?

    private var avisados: [String: Radar] = [:]

    public init(radares: [Radar], ajustes: AjustesMotor = AjustesMotor()) {
        self.indice = IndiceRadares(radares)
        self.ajustes = ajustes
    }

    public func cambiar(radares: [Radar]) {
        indice = IndiceRadares(radares)
        reiniciar()
    }

    public func reiniciar() {
        avisados = [:]
        proximo = nil
        tramo = nil
        distanciaMasCercano = nil
    }

    /// true cuando hace falta el GPS a máxima precisión (radar a menos de 10 km o dentro de un tramo).
    public var necesitaPrecision: Bool {
        if tramo != nil { return true }
        guard let d = distanciaMasCercano else { return false }
        return d < 10_000
    }

    /// Distancia a la que toca avisar a esta velocidad (m/s).
    public func distanciaDeAviso(velocidad: Double) -> Double {
        min(ajustes.distanciaMaxima, max(ajustes.distanciaMinima, velocidad * ajustes.segundosAntelacion))
    }

    /// ¿Está el radar delante, en la carretera por la que vamos?
    /// Sin mapa no se sabe la carretera: se acepta un pasillo estrecho en el sentido de la marcha
    /// (70 m a cada lado, o un 20 % de la distancia), que deja fuera casi todas las vías paralelas.
    func delante(_ r: Radar, desde p: Posicion, distancia d: Double) -> Bool {
        let giro = Geo.diferencia(p.rumbo, Geo.rumbo(p.lat, p.lon, r.lat, r.lon)) * .pi / 180
        let avance = d * cos(giro)
        let lateral = abs(d * sin(giro))
        guard avance > 0, lateral <= max(70, 0.2 * d) else { return false }
        if let sentido = r.rumbo, abs(Geo.diferencia(p.rumbo, sentido)) > 60 { return false }
        return true
    }

    public func procesar(_ p: Posicion) -> [Evento] {
        var eventos: [Evento] = []
        distanciaMasCercano = indice.distanciaAlMasCercano(lat: p.lat, lon: p.lon, tope: 15_000)

        // Rearme: olvidar los radares avisados de los que ya nos hemos alejado.
        for (id, r) in avisados where Geo.distancia(p.lat, p.lon, r.lat, r.lon) > ajustes.rearme {
            avisados[id] = nil
        }

        eventos += seguirTramo(p)

        guard p.precision >= 0, p.precision <= ajustes.precisionMaxima,
              p.velocidad >= ajustes.velocidadMinima, p.rumbo >= 0 else {
            proximo = nil
            return eventos
        }

        let aviso = distanciaDeAviso(velocidad: p.velocidad)
        let candidatos = indice.cercanos(lat: p.lat, lon: p.lon, radio: 2_500)
            .filter { delante($0.radar, desde: p, distancia: $0.distancia) }
        proximo = candidatos.first.map { ($0.radar, $0.distancia) }

        for c in candidatos where c.distancia <= aviso && avisados[c.radar.id] == nil {
            avisados[c.radar.id] = c.radar
            eventos.append(.radar(c.radar, distancia: c.distancia, velocidad: p.kmh))
            if c.radar.tipo == .tramo, tramo == nil, c.radar.longitud != nil || c.radar.finLat != nil {
                tramo = EstadoTramo(radar: c.radar)
            }
        }
        return eventos
    }

    private func seguirTramo(_ p: Posicion) -> [Evento] {
        guard var t = tramo else { return [] }
        let r = t.radar
        let alInicio = Geo.distancia(p.lat, p.lon, r.lat, r.lon)

        if !t.dentro {
            t.menorDistancia = min(t.menorDistancia, alInicio)
            if alInicio < 60 || (t.menorDistancia < 200 && alInicio > t.menorDistancia + 30) {
                // Hemos pasado por el inicio: empieza la cuenta.
                t.dentro = true
                t.ultima = p
            } else if alInicio > t.menorDistancia + 600 {
                tramo = nil   // nos hemos ido por otro lado
                return []
            }
            tramo = t
            return []
        }

        guard let anterior = t.ultima else { tramo = nil; return [] }
        let dt = p.instante - anterior.instante
        guard dt > 0 else { return [] }
        if dt > 30 { tramo = nil; return [] }   // GPS perdido: la media ya no vale
        t.recorrido += Geo.distancia(anterior.lat, anterior.lon, p.lat, p.lon)
        t.tiempo += dt
        t.ultima = p

        var eventos: [Evento] = []
        var fin = false
        if let fLat = r.finLat, let fLon = r.finLon {
            let recta = Geo.distancia(r.lat, r.lon, fLat, fLon)
            if Geo.distancia(p.lat, p.lon, fLat, fLon) < 80 { fin = true }
            if t.recorrido > (r.longitud ?? recta * 1.6 + 500) * 1.15 + 300 { tramo = nil; return [] }
        } else if let largo = r.longitud, t.recorrido >= largo {
            fin = true
        }

        if fin {
            if let media = t.media { eventos.append(.finTramo(r, media: media)) }
            tramo = nil
            return eventos
        }
        if !t.excesoAvisado, t.recorrido > 500, let limite = r.limite, let media = t.media,
           media > limite + ajustes.margenTramo {
            t.excesoAvisado = true
            eventos.append(.excesoTramo(r, media: media))
        }
        tramo = t
        return eventos
    }
}

/// Lo que dice la voz.
public enum Frases {
    /// Distancia redondeada como se dice en voz alta.
    public static func distancia(_ metros: Double) -> String {
        if metros >= 950 {
            let km = (metros / 100).rounded() / 10
            if km == km.rounded() { return km == 1 ? "1 kilómetro" : "\(Int(km)) kilómetros" }
            return String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",") + " kilómetros"
        }
        let m = max(50, Int((metros / 50).rounded()) * 50)
        return "\(m) metros"
    }

    public static func texto(_ evento: Evento) -> String {
        switch evento {
        case let .radar(r, d, velocidad):
            var s = (r.tipo == .tramo ? "Radar de tramo a " : "Radar a ") + distancia(d) + "."
            if r.tipo == .tramo, let largo = r.longitud, largo >= 500 { s += " Dura " + distancia(largo) + "." }
            if let limite = r.limite {
                s += " Límite \(limite)."
                if velocidad > limite + 3 { s += " Vas a \(velocidad)." }
            }
            return s
        case let .excesoTramo(r, media):
            return "Media del tramo \(media)." + (r.limite.map { " Límite \($0)." } ?? "")
        case let .finTramo(_, media):
            return "Fin del tramo. Media \(media)."
        }
    }
}
