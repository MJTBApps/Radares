import Foundation

/// Comprueba en el App Store si hay una versión más nueva que la instalada.
/// Solo consulta el número de versión público de la app: no envía nada del usuario.
@MainActor
final class Actualizacion: ObservableObject {
    @Published private(set) var nueva: String?
    @Published private(set) var enlace: URL?

    private var actual: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func comprobar() async {
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=es.mjtbapps.radares&country=es") else { return }
        do {
            let (datos, _) = try await URLSession.shared.data(from: url)
            struct Respuesta: Decodable {
                struct App: Decodable { let version: String; let trackViewUrl: String? }
                let results: [App]
            }
            guard let app = try JSONDecoder().decode(Respuesta.self, from: datos).results.first else { return }
            if Self.esMasNueva(app.version, que: actual) {
                nueva = app.version
                enlace = app.trackViewUrl.flatMap(URL.init(string:))
            } else {
                nueva = nil
            }
        } catch {}
    }

    /// Compara «1.2.0» con «1.10» número a número.
    nonisolated static func esMasNueva(_ a: String, que b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
