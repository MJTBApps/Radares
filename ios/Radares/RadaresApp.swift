import SwiftUI

@main
struct RadaresApp: App {
    @StateObject private var modelo = Modelo()
    @StateObject private var tienda = Tienda()
    @StateObject private var actualizacion = Actualizacion()
    @Environment(\.scenePhase) private var fase

    var body: some Scene {
        WindowGroup {
            Pantalla()
                .environmentObject(modelo)
                .environmentObject(tienda)
                .environmentObject(actualizacion)
                .onReceive(tienda.$esPremium) { valor in
                    if let valor, valor != modelo.premium { modelo.premium = valor }
                }
        }
        .onChange(of: fase) { nueva in
            guard nueva == .active else { return }
            modelo.alPasarAlFrente()
            Task { await actualizacion.comprobar() }
            // Espera a que la tienda confirme si hay Premium antes de decidir el anuncio.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Anuncios.shared.alAbrir { [modelo] in
                    // Sin Premium, con la app abierta por el usuario y sin ir rápido.
                    !modelo.premium && !modelo.arrancadaSola && (modelo.kmh ?? 0) < 10
                }
            }
        }
    }
}
