import GoogleMobileAds
import SwiftUI
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
        // Anuncios no personalizados: la app no hace seguimiento (ni pide permiso de rastreo).
        let peticion = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        peticion.register(extras)
        AppOpenAd.load(with: Self.bloqueAlAbrir, request: peticion) { [weak self] anuncio, _ in
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

/// Banner de AdMob al pie de la pantalla, solo sin Premium y con el consentimiento ya resuelto.
struct BannerAnuncio: UIViewRepresentable {
    static let bloque = "ca-app-pub-1535697166232113/8702045036"
    let ancho: CGFloat

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: ancho))
        banner.adUnitID = Self.bloque
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow }?.rootViewController }.first
        MobileAds.shared.start(completionHandler: nil)
        let peticion = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        peticion.register(extras)
        banner.load(peticion)
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    static func alto(_ ancho: CGFloat) -> CGFloat { currentOrientationAnchoredAdaptiveBanner(width: ancho).size.height }
}
