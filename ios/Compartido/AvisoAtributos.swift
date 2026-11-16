#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Datos de la tarjeta de la pantalla de bloqueo y la isla dinámica (actividad en directo).
/// Lo comparten la app y la extensión `Aviso`.
struct AvisoAtributos: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var kmh: Int?
        /// «Radar», «Radar de tramo» o «Dentro de un tramo». nil = ningún radar delante.
        var titulo: String?
        /// Metros hasta el radar.
        var distancia: Int?
        var limite: Int?
        var via: String?
        /// Media del tramo en curso.
        var media: Int?
    }
}
#endif
