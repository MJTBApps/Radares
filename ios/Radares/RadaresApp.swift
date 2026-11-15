import SwiftUI

@main
struct RadaresApp: App {
    @StateObject private var modelo = Modelo()
    @StateObject private var tienda = Tienda()

    var body: some Scene {
        WindowGroup {
            Pantalla()
                .environmentObject(modelo)
                .environmentObject(tienda)
                .onReceive(tienda.$esPremium) { valor in
                    if let valor, valor != modelo.premium { modelo.premium = valor }
                }
        }
    }
}
