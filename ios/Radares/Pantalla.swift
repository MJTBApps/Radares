import CoreLocation
import RadaresCore
import SwiftUI

struct Pantalla: View {
    @EnvironmentObject private var modelo: Modelo
    @Environment(\.openURL) private var abrir

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                velocidad
                if let tramo = modelo.tramo, tramo.dentro { tarjetaTramo(tramo) }
                tarjetaRadar
                botonPrincipal
                if modelo.permiso == .denied || modelo.permiso == .restricted { avisoPermiso }
                sonido
                Toggle("Empezar al abrir la app", isOn: $modelo.empezarAlAbrir)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                if !modelo.diario.isEmpty { diario }
                pie
            }
            .padding(16)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Piezas

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
            if modelo.activo { modelo.parar() } else { modelo.empezar() }
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
            Text("No avisa de radares móviles. Respeta siempre los límites.")
            Text("Datos: © colaboradores de OpenStreetMap (ODbL), Servei Català de Trànsit y DGT.")
        }
        .font(.footnote)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.top, 4)
    }
}
