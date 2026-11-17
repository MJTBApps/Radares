import GoogleMobileAds
import UIKit
import UserMessagingPlatform

/// Un anuncio de Google (AdMob) al abrir la app, solo sin Premium.
/// Nunca durante la vigilancia ni cuando la app ha arrancado sola en el coche.
/// Antes, en Europa, Google muestra su formulario de consentimiento (RGPD).
@MainActor
final class Anuncios: NSObject, FullScreenContentDelegate {
    static let shared = Anuncios()

    // Identificadores de AdMob. El de la app va también en project.yml (GADApplicationIdentifier).
    static let bloqueAlAbrir = "ca-app-pub-1535697166232113/5558555109"

    private var iniciado = false
    private var mostrando = false
    private var ultimo: Date?

    /// Al abrir la app. `puede` se vuelve a consultar justo antes de mostrarlo.
    func alAbrir(puede: @escaping () -> Bool) {
        guard puede(), !mostrando else { return }
        // Como mucho uno cada 4 horas: abrir y cerrar no debe llenarse de anuncios.
        if let u = ultimo, Date().timeIntervalSince(u) < 4 * 3600 { return }
        guard let raiz = Self.raiz() else { return }

        let consentimiento = ConsentInformation.shared
        consentimiento.requestConsentInfoUpdate(with: RequestParameters()) { [weak self] _ in
            ConsentForm.loadAndPresentIfRequired(from: raiz) { _ in
                Task { @MainActor in
                    guard let self, consentimiento.canRequestAds else { return }
                    self.cargarYMostrar(puede: puede)
                }
            }
        }
    }

    private func cargarYMostrar(puede: @escaping () -> Bool) {
        if !iniciado {
            MobileAds.shared.start(completionHandler: nil)
            iniciado = true
        }
        let pedido = Date()
        AppOpenAd.load(with: Self.bloqueAlAbrir, request: Request()) { [weak self] anuncio, _ in
            Task { @MainActor in
                // Si tarda más de 5 s ya no se muestra: el usuario estará usando la app.
                guard let self, let anuncio, Date().timeIntervalSince(pedido) < 5,
                      puede(), let raiz = Self.raiz() else { return }
                anuncio.fullScreenContentDelegate = self
                self.mostrando = true
                self.ultimo = Date()
                anuncio.present(from: raiz)
            }
        }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.mostrando = false }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.mostrando = false }
    }

    private static func raiz() -> UIViewController? {
        let escena = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var vc = escena?.windows.first { $0.isKeyWindow }?.rootViewController
        while let siguiente = vc?.presentedViewController { vc = siguiente }
        return vc
    }
}
