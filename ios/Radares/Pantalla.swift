import CoreLocation
import RadaresCore
import GoogleMobileAds
import StoreKit
import SwiftUI
import UserMessagingPlatform

/// Páginas públicas de la app (política de privacidad y condiciones de uso).
enum Enlaces {
    static let privacidad = URL(string: "https://mjtbapps.github.io/chivato-radar/privacidad.html")!
    static let condiciones = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

struct Pantalla: View {
    @EnvironmentObject private var modelo: Modelo
    @EnvironmentObject private var tienda: Tienda
    @EnvironmentObject private var actualizacion: Actualizacion
    @Environment(\.openURL) private var abrir
    @State private var verPremium = false
    @State private var puedeAnuncios = ConsentInformation.shared.canRequestAds

    private let rojo = Color(red: 0.83, green: 0.18, blue: 0.18)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Chivato Radar").font(.title2.weight(.bold))
                if let v = actualizacion.nueva { avisoActualizacion(v) }
                velocidad
                if let tramo = modelo.tramo, tramo.dentro { tarjetaTramo(tramo) } else { tarjetaRadar }
                botonPrincipal
                if modelo.permiso == .denied || modelo.permiso == .restricted { avisoPermiso }
                Text("Ajustes").font(.title3.weight(.bold)).padding(.top, 6)
                sonido
                arranque
                tarjetaPremium
                if !modelo.diario.isEmpty { diario }
                pie
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            // Banner solo sin Premium (Premium quita los anuncios).
            if !modelo.premium && puedeAnuncios {
                BannerAnuncio(ancho: UIScreen.main.bounds.width)
                    .frame(height: BannerAnuncio.alto(UIScreen.main.bounds.width))
                    .background(Color(.systemBackground))
            }
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            // El consentimiento se resuelve al abrir (Anuncios.alAbrir); hasta entonces, sin banner.
            if !puedeAnuncios && ConsentInformation.shared.canRequestAds { puedeAnuncios = true }
        }
        .sheet(isPresented: $verPremium) {
            PantallaPremium().environmentObject(modelo).environmentObject(tienda)
        }
    }

    // MARK: - Piezas

    private func tarjeta<C: View>(@ViewBuilder _ contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { contenido() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Señal de límite: círculo blanco con borde rojo.
    private func senal(_ valor: Int, tam: CGFloat = 56) -> some View {
        Text("\(valor)")
            .font(.system(size: tam * 0.38, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .frame(width: tam, height: tam)
            .background(Circle().fill(Color.white))
            .overlay(Circle().stroke(rojo, lineWidth: tam / 9))
    }

    private func interruptor(_ titulo: String, _ explicacion: String, _ valor: Binding<Bool>) -> some View {
        Toggle(isOn: valor) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.body.weight(.semibold))
                Text(explicacion).font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private func avisoActualizacion(_ version: String) -> some View {
        Button {
            if let url = actualizacion.enlace { abrir(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hay una versión nueva (\(version))").font(.headline)
                    Text("Toca para actualizar en el App Store.").font(.subheadline)
                }
                Spacer()
            }
            .foregroundColor(.white)
            .padding()
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Velocidad dentro de un anillo: color de la app mientras vigila, rojo si vas por encima del límite.
    private var velocidad: some View {
        let anillo: Color = pasado ? rojo : (modelo.activo ? .accentColor : Color(.systemGray4))
        return ZStack {
            Circle().stroke(anillo, lineWidth: 10)
            VStack(spacing: 0) {
                Text(modelo.kmh.map(String.init) ?? "–")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(pasado ? rojo : .primary)
                Text("km/h").font(.subheadline).foregroundColor(.secondary)
            }
        }
        .frame(width: 200, height: 200)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Vamos por encima del límite del radar que tenemos delante.
    private var pasado: Bool {
        guard let kmh = modelo.kmh, let limite = modelo.proximo?.limite,
              let d = modelo.distanciaProximo, d < 1500 else { return false }
        return kmh > limite
    }

    private var tarjetaRadar: some View {
        tarjeta {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let radar = modelo.proximo, let d = modelo.distanciaProximo {
                        Text(radar.tipo == .tramo ? "Radar de tramo" : "Radar").font(.headline)
                        Text(Frases.distancia(d)).font(.system(size: 30, weight: .bold, design: .rounded))
                        if let via = radar.via { Text(via).font(.subheadline).foregroundColor(.secondary) }
                    } else if !modelo.activo {
                        Text("Parado").font(.headline)
                        Text("Pulsa Empezar antes de salir. Puedes bloquear el móvil o usar otras apps.")
                            .font(.subheadline).foregroundColor(.secondary)
                    } else if modelo.ahorro {
                        Text("Sin radares cerca").font(.headline)
                        Text("GPS en modo de ahorro.").font(.subheadline).foregroundColor(.secondary)
                    } else {
                        Text("Ningún radar delante").font(.headline)
                        Text("Te aviso unos 20 segundos antes.").font(.subheadline).foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if modelo.distanciaProximo != nil, let limite = modelo.proximo?.limite { senal(limite) }
            }
        }
    }

    private func tarjetaTramo(_ tramo: EstadoTramo) -> some View {
        let media = tramo.media
        let exceso = media != nil && tramo.radar.limite != nil && media! > tramo.radar.limite!
        return tarjeta {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dentro de un tramo").font(.headline)
                    Text("Media " + (media.map(String.init) ?? "–") + " km/h")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(exceso ? rojo : .primary)
                    if let quedan = tramo.restante {
                        Text("Quedan " + Frases.distancia(quedan)).font(.subheadline).foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let limite = tramo.radar.limite { senal(limite) }
            }
        }
    }

    private var botonPrincipal: some View {
        Button {
            if modelo.activo { modelo.parar(manual: true) } else { modelo.empezar() }
        } label: {
            Text(modelo.activo ? "Parar" : "Empezar")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(modelo.activo ? rojo : Color.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var avisoPermiso: some View {
        tarjeta {
            Label("La app no tiene permiso de ubicación", systemImage: "location.slash.fill").font(.headline)
            Text("Sin la posición no puede saber qué radares tienes delante.")
                .font(.subheadline).foregroundColor(.secondary)
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) { abrir(url) }
            }
        }
    }

    private var sonido: some View {
        tarjeta {
            Text("Dónde suena el aviso").font(.body.weight(.semibold))
            Menu {
                Picker("Dónde suena el aviso", selection: $modelo.salida) {
                    ForEach(SalidaVoz.allCases) { modo in Text(modo.titulo).tag(modo) }
                }
            } label: {
                HStack {
                    Text(modelo.salida.titulo).foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").foregroundColor(.accentColor)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text(modelo.salida.explicacion).font(.footnote).foregroundColor(.secondary)
            if modelo.salida == .llamada && !modelo.llamadaDisponible {
                Label("La prueba ha terminado: ahora suena por el altavoz del iPhone.", systemImage: "lock.fill")
                    .font(.footnote).foregroundColor(.orange)
                Button("Volver a oírlo por el coche") { verPremium = true }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                Button("Probar el aviso") { modelo.probarSonido() }
                Spacer()
                Button("Probar en 10 s") { modelo.probarSonido(dentroDe: 10) }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            Text("«Probar en 10 s» sirve para bloquear el móvil y comprobar que suena igual.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }

    private var tarjetaPremium: some View {
        tarjeta {
            if modelo.premium {
                Label("Premium activo", systemImage: "checkmark.seal.fill").font(.headline)
                Text("Avisos por los altavoces del coche, arranque automático y sin anuncios. Gracias por apoyar la app.")
                    .font(.subheadline).foregroundColor(.secondary)
            } else {
                Label("Premium", systemImage: "star.fill").font(.headline)
                let dias = modelo.diasDePruebaRestantes
                Text(dias > 0
                     ? "Premium: avisos por los altavoces del coche, arranque automático y sin anuncios. Lo estás probando gratis: " + (dias == 1 ? "queda 1 día." : "quedan \(dias) días.")
                     : "Premium: avisos por los altavoces del coche, arranque automático y sin anuncios. Los avisos por el iPhone siguen siendo gratis.")
                    .font(.subheadline).foregroundColor(.secondary)
                Button("Ver Premium") { verPremium = true }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
    }

    private var arranque: some View {
        tarjeta {
            // Es de Premium (o durante los días de prueba); si no, abre la hoja de Premium.
            interruptor("Empezar sola al ir en coche",
                        "Premium. Se pone a vigilar sola al ir en coche y se apaga al aparcar.",
                        Binding(get: { modelo.arranqueAutomatico && modelo.llamadaDisponible },
                                set: { nuevo in
                                    if nuevo && !modelo.llamadaDisponible { verPremium = true }
                                    else { modelo.arranqueAutomatico = nuevo }
                                }))
            if modelo.arranqueAutomatico && modelo.permiso != .authorizedAlways {
                HStack {
                    Label("Necesita la ubicación «Siempre».", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundColor(.orange)
                    Spacer()
                    Button("Ajustes") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { abrir(url) }
                    }
                    .font(.footnote)
                }
            }
            Divider()
            interruptor("Empezar al abrir la app", "Vigila nada más abrirla, sin pulsar Empezar.", $modelo.empezarAlAbrir)
            Divider()
            interruptor("Avisos de tráfico de la DGT",
                        "Accidentes, retenciones y obstáculos en tu carretera, a unos 2 km.", $modelo.avisosDGT)
            Divider()
            interruptor("Aviso en la pantalla de bloqueo",
                        "El próximo radar en la pantalla de bloqueo y en la isla dinámica.", $modelo.pantallaBloqueo)
        }
    }

    private var diario: some View {
        tarjeta {
            Text("Últimos avisos").font(.headline)
            ForEach(Array(modelo.diario.prefix(6).enumerated()), id: \.offset) { _, linea in
                Text(linea).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var pie: some View {
        VStack(spacing: 4) {
            Text("\(modelo.totalRadares) radares fijos y de tramo · datos del \(modelo.fechaDatos)")
            if let n = modelo.totalIncidencias { Text("\(n) incidencias de la DGT en este momento") }
            Text("No avisa de radares móviles. Respeta siempre los límites.")
            Text("Datos: © colaboradores de OpenStreetMap (ODbL), Servei Català de Trànsit y DGT.")
            Link("Política de privacidad", destination: Enlaces.privacidad)
        }
        .font(.footnote)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

/// Hoja de compra de Premium.
struct PantallaPremium: View {
    @EnvironmentObject private var modelo: Modelo
    @EnvironmentObject private var tienda: Tienda
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Los avisos, por los altavoces del coche")
                        .font(.title2.weight(.bold))
                    Text("Con Premium el aviso entra por el canal de llamadas: el coche baja su música y lo dice por sus altavoces, aunque estés usando su navegador y su música. Sin CarPlay y sin cambiar de fuente.")
                        .foregroundColor(.secondary)
                    Label("Avisos de radares fijos y de tramo: gratis, por el iPhone", systemImage: "checkmark")
                    Label("Avisos por los altavoces del coche: Premium", systemImage: "star.fill")
                    Label("Empezar sola al ir en coche: Premium", systemImage: "star.fill")
                    Label("Sin anuncios: Premium", systemImage: "star.fill")

                    if modelo.premium {
                        Label("Ya tienes Premium", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundColor(.green)
                    } else if tienda.productos.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Cargando precios…").foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(tienda.productos, id: \.id) { producto in
                            Button {
                                Task { await tienda.comprar(producto) }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(producto.displayName).font(.headline)
                                    Text(precio(producto)).font(.subheadline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(tienda.ocupada)
                        }
                    }

                    if let aviso = tienda.aviso {
                        Text(aviso).font(.subheadline).foregroundColor(.orange)
                    }

                    Button("Restaurar compras") { Task { await tienda.restaurar() } }
                        .disabled(tienda.ocupada)

                    Text("La suscripción anual se renueva sola cada año al mismo precio hasta que la canceles en Ajustes → tu nombre → Suscripciones, como mínimo 24 horas antes de la renovación. El pago se carga en tu cuenta de Apple al confirmar la compra.")
                        .font(.footnote).foregroundColor(.secondary)
                    HStack(spacing: 16) {
                        Link("Condiciones de uso", destination: Enlaces.condiciones)
                        Link("Política de privacidad", destination: Enlaces.privacidad)
                    }
                    .font(.footnote)
                }
                .padding(20)
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cerrar() } }
            }
            .task { await tienda.cargar() }
            .onChange(of: modelo.premium) { ahora in if ahora { cerrar() } }
        }
    }

    private func precio(_ producto: Product) -> String {
        producto.type == .autoRenewable ? "\(producto.displayPrice) al año" : "\(producto.displayPrice), un solo pago"
    }
}
