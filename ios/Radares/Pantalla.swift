import CoreLocation
import RadaresCore
import StoreKit
import SwiftUI

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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let v = actualizacion.nueva { avisoActualizacion(v) }
                velocidad
                if let tramo = modelo.tramo, tramo.dentro { tarjetaTramo(tramo) }
                tarjetaRadar
                botonPrincipal
                if modelo.permiso == .denied || modelo.permiso == .restricted { avisoPermiso }
                sonido
                tarjetaPremium
                arranque
                if !modelo.diario.isEmpty { diario }
                pie
            }
            .padding(16)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $verPremium) {
            PantallaPremium().environmentObject(modelo).environmentObject(tienda)
        }
    }

    // MARK: - Piezas

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
            .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var velocidad: some View {
        VStack(spacing: 0) {
            Text(modelo.kmh.map(String.init) ?? "–")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(pasado ? .red : .primary)
            Text("km/h").font(.title3).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    /// Vamos por encima del límite del radar que tenemos delante.
    private var pasado: Bool {
        guard let kmh = modelo.kmh, let limite = modelo.proximo?.limite,
              let d = modelo.distanciaProximo, d < 1500 else { return false }
        return kmh > limite
    }

    private var tarjetaRadar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let radar = modelo.proximo, let d = modelo.distanciaProximo {
                Text(radar.tipo == .tramo ? "Radar de tramo" : "Radar")
                    .font(.headline)
                Text(Frases.distancia(d))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                HStack(spacing: 12) {
                    if let limite = radar.limite { Label("Límite \(limite)", systemImage: "speedometer") }
                    if let via = radar.via { Label(via, systemImage: "road.lanes") }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            } else if !modelo.activo {
                Text("Parado").font(.headline)
                Text("Pulsa Empezar antes de salir. Puedes bloquear el móvil o usar otras apps.")
                    .font(.subheadline).foregroundColor(.secondary)
            } else if modelo.ahorro {
                Text("Sin radares a menos de 10 km").font(.headline)
                Text("GPS en modo de ahorro.").font(.subheadline).foregroundColor(.secondary)
            } else {
                Text("Ningún radar delante").font(.headline)
                Text("Avisaré unos 20 segundos antes.").font(.subheadline).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func tarjetaTramo(_ tramo: EstadoTramo) -> some View {
        let media = tramo.media
        let exceso = media != nil && tramo.radar.limite != nil && media! > tramo.radar.limite!
        return VStack(alignment: .leading, spacing: 6) {
            Text("Dentro de un tramo").font(.headline)
            Text("Media " + (media.map(String.init) ?? "–") + " km/h")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(exceso ? .red : .primary)
            HStack(spacing: 12) {
                if let limite = tramo.radar.limite { Label("Límite \(limite)", systemImage: "speedometer") }
                if let quedan = tramo.restante { Label("Quedan " + Frases.distancia(quedan), systemImage: "flag.checkered") }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var botonPrincipal: some View {
        Button {
            if modelo.activo { modelo.parar(manual: true) } else { modelo.empezar() }
        } label: {
            Text(modelo.activo ? "Parar" : "Empezar")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(modelo.activo ? .red : .accentColor)
    }

    private var avisoPermiso: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("La app no tiene permiso de ubicación").font(.headline)
            Text("Sin la posición no puede saber qué radares tienes delante.")
                .font(.subheadline).foregroundColor(.secondary)
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) { abrir(url) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var sonido: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dónde suena el aviso").font(.headline)
            Picker("Dónde suena el aviso", selection: $modelo.salida) {
                ForEach(SalidaVoz.allCases) { modo in Text(modo.titulo).tag(modo) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Text(modelo.salida.explicacion)
                .font(.subheadline).foregroundColor(.secondary)
            if modelo.salida == .llamada && !modelo.llamadaDisponible {
                Label("La prueba ha terminado: ahora suena por el altavoz del iPhone.", systemImage: "lock.fill")
                    .font(.subheadline).foregroundColor(.orange)
                Button("Volver a oírlo por el coche") { verPremium = true }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                Button("Probar ahora") { modelo.probarSonido() }
                Spacer()
                Button("Probar en 10 s") { modelo.probarSonido(dentroDe: 10) }
            }
            .buttonStyle(.bordered)
            Text("«Probar en 10 s» sirve para bloquear el móvil y comprobar que suena igual. Con la app parada puede no sonar en segundo plano.")
                .font(.footnote).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var tarjetaPremium: some View {
        VStack(alignment: .leading, spacing: 8) {
            if modelo.premium {
                Label("Premium activo", systemImage: "checkmark.seal.fill").font(.headline)
                Text("El aviso por los altavoces del coche está desbloqueado. Gracias por apoyar la app.")
                    .font(.subheadline).foregroundColor(.secondary)
            } else {
                Label("Premium", systemImage: "star.fill").font(.headline)
                let dias = modelo.diasDePruebaRestantes
                Text(dias > 0
                     ? "El aviso por los altavoces del coche es de Premium. Lo estás probando gratis: " + (dias == 1 ? "queda 1 día." : "quedan \(dias) días.")
                     : "El aviso por los altavoces del coche es de Premium. Los avisos por el iPhone siguen siendo gratis.")
                    .font(.subheadline).foregroundColor(.secondary)
                Button("Ver Premium") { verPremium = true }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var arranque: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Empezar sola al ir en coche", isOn: $modelo.arranqueAutomatico)
            Text("Detecta que vas en coche y se pone a vigilar sin que abras la app. Al aparcar se apaga sola.")
                .font(.subheadline).foregroundColor(.secondary)
            if modelo.arranqueAutomatico && modelo.permiso != .authorizedAlways {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Necesita la ubicación «Siempre».", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundColor(.orange)
                    Button("Abrir Ajustes") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { abrir(url) }
                    }
                    .font(.subheadline)
                }
            }
            Divider()
            Toggle("Empezar al abrir la app", isOn: $modelo.empezarAlAbrir)
            Divider()
            Toggle("Avisos de tráfico de la DGT", isOn: $modelo.avisosDGT)
            Text("Accidentes, retenciones, obstáculos y mal tiempo en tu carretera, a unos 2 km. Usa unos 2 MB de datos por hora de viaje.")
                .font(.subheadline).foregroundColor(.secondary)
            Divider()
            Toggle("Aviso en la pantalla de bloqueo", isOn: $modelo.pantallaBloqueo)
            Text("El próximo radar, la distancia y el límite en la pantalla de bloqueo y en la isla dinámica.")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var diario: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Últimos avisos").font(.headline)
            ForEach(Array(modelo.diario.prefix(8).enumerated()), id: \.offset) { _, linea in
                Text(linea).font(.footnote).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
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
