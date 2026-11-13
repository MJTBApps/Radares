import SwiftUI

@main
struct RadaresApp: App {
    @StateObject private var modelo = Modelo()

    var body: some Scene {
        WindowGroup {
            Pantalla().environmentObject(modelo)
        }
    }
}
