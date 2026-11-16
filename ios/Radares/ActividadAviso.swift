import Foundation
import RadaresCore
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Mantiene la tarjeta de la pantalla de bloqueo (actividad en directo, iOS 16.2+).
/// Se actualiza desde la app mientras vigila; como mucho cada 3 segundos para no gastar.
final class ActividadAviso {
    private var ultima = Date.distantPast
    private var ultimoEstado: Any?
    private var actual: Any?

    func empezar() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled, actual == nil else { return }
        let estado = AvisoAtributos.ContentState()
        do {
            actual = try Activity.request(attributes: AvisoAtributos(),
                                          content: ActivityContent(state: estado, staleDate: nil))
        } catch {
            actual = nil
        }
        #endif
    }

    func actualizar(kmh: Int?, radar: Radar?, distancia: Double?, tramo: EstadoTramo?) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *), let actividad = actual as? Activity<AvisoAtributos> else { return }
        var e = AvisoAtributos.ContentState()
        e.kmh = kmh
        if let t = tramo, t.dentro {
            e.titulo = "Dentro de un tramo"
            e.media = t.media
            e.limite = t.radar.limite
            e.via = t.radar.via
            e.distancia = t.restante.map { Int($0) }
        } else if let r = radar, let d = distancia {
            e.titulo = r.tipo == .tramo ? "Radar de tramo" : "Radar"
            e.distancia = Int((d / 50).rounded() * 50)
            e.limite = r.limite
            e.via = r.via
        }
        if let previo = ultimoEstado as? AvisoAtributos.ContentState, previo == e { return }
        // Cambios de radar al momento; los de velocidad y distancia, cada 3 s.
        let cambiaRadar = (ultimoEstado as? AvisoAtributos.ContentState)?.titulo != e.titulo
        guard cambiaRadar || Date().timeIntervalSince(ultima) >= 3 else { return }
        ultima = Date()
        ultimoEstado = e
        Task { await actividad.update(ActivityContent(state: e, staleDate: Date().addingTimeInterval(120))) }
        #endif
    }

    func terminar() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *), let actividad = actual as? Activity<AvisoAtributos> else { return }
        actual = nil
        ultimoEstado = nil
        Task { await actividad.end(nil, dismissalPolicy: .immediate) }
        #endif
    }

    /// Cierra tarjetas que quedaran abiertas de una ejecución anterior (la app se cerró sin parar).
    func terminarHuerfanas() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        for a in Activity<AvisoAtributos>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }
}
