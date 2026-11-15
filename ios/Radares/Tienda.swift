import Foundation
import StoreKit

/// Compras dentro de la app (StoreKit 2). Premium es una suscripción anual o un pago único;
/// cualquiera de los dos desbloquea el aviso por los altavoces del coche.
/// Los productos se crean en App Store Connect con estos mismos identificadores.
@MainActor
final class Tienda: ObservableObject {
    static let anual = "es.mjtbapps.radares.premium.anual"
    static let siempre = "es.mjtbapps.radares.premium.siempre"

    @Published private(set) var productos: [Product] = []
    /// nil hasta que el App Store contesta: así no se pisa lo que la app recordaba de la última vez.
    @Published private(set) var esPremium: Bool?
    @Published private(set) var ocupada = false
    @Published var aviso: String?

    private var escucha: Task<Void, Never>?

    init() {
        // Compras hechas fuera de la app (otro dispositivo, renovaciones, reembolsos).
        escucha = Task { [weak self] in
            for await resultado in Transaction.updates {
                if case .verified(let transaccion) = resultado { await transaccion.finish() }
                await self?.actualizar()
            }
        }
        Task { [weak self] in
            await self?.actualizar()
            await self?.cargar()
        }
    }

    func cargar() async {
        guard productos.isEmpty else { return }
        do {
            let lista = try await Product.products(for: [Tienda.anual, Tienda.siempre])
            productos = lista.sorted { $0.price < $1.price }
            if lista.isEmpty { aviso = "La tienda no está disponible ahora. Inténtalo más tarde." }
        } catch {
            aviso = "No se ha podido conectar con el App Store: \(error.localizedDescription)"
        }
    }

    func comprar(_ producto: Product) async {
        ocupada = true
        defer { ocupada = false }
        do {
            switch try await producto.purchase() {
            case .success(.verified(let transaccion)):
                await transaccion.finish()
                await actualizar()
            case .success(.unverified):
                aviso = "El App Store no ha podido verificar la compra."
            case .pending:
                aviso = "La compra está pendiente de aprobación."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            aviso = "No se ha podido comprar: \(error.localizedDescription)"
        }
    }

    func restaurar() async {
        ocupada = true
        defer { ocupada = false }
        do {
            try await AppStore.sync()
            await actualizar()
            if esPremium != true { aviso = "No hay ninguna compra de Premium en esta cuenta de Apple." }
        } catch {
            aviso = "No se han podido restaurar las compras: \(error.localizedDescription)"
        }
    }

    private func actualizar() async {
        var tiene = false
        for await resultado in Transaction.currentEntitlements {
            guard case .verified(let transaccion) = resultado, transaccion.revocationDate == nil else { continue }
            if transaccion.productID == Tienda.anual || transaccion.productID == Tienda.siempre { tiene = true }
        }
        esPremium = tiene
    }
}
