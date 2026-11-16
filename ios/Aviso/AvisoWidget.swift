import ActivityKit
import SwiftUI
import WidgetKit

/// Tarjeta de la pantalla de bloqueo y de la isla dinámica mientras la app vigila.
@main
struct AvisoBundle: WidgetBundle {
    var body: some Widget {
        AvisoEnDirecto()
    }
}

struct AvisoEnDirecto: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AvisoAtributos.self) { contexto in
            Bloqueo(estado: contexto.state)
                .padding(16)
                .activityBackgroundTint(Color(red: 0.07, green: 0.15, blue: 0.33))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { contexto in
            let e = contexto.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Icono(estado: e).font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let limite = e.limite { Limite(valor: limite, tamano: 40) }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(e.titulo ?? "Sin radares delante").font(.headline)
                        Text(detalle(e)).font(.subheadline).foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let kmh = e.kmh { Text("Vas a \(kmh) km/h").font(.caption).foregroundColor(.secondary) }
                }
            } compactLeading: {
                Icono(estado: e)
            } compactTrailing: {
                Text(corto(e)).font(.caption.monospacedDigit())
            } minimal: {
                Icono(estado: e)
            }
        }
    }
}

private func distancia(_ m: Int) -> String {
    m >= 1_000 ? String(format: "%.1f km", Double(m) / 1_000).replacingOccurrences(of: ".", with: ",") : "\(m) m"
}

private func detalle(_ e: AvisoAtributos.ContentState) -> String {
    if let media = e.media { return "Media \(media)" + (e.distancia.map { " · quedan " + distancia($0) } ?? "") }
    var partes: [String] = []
    if let d = e.distancia { partes.append(distancia(d)) }
    if let via = e.via { partes.append(via) }
    return partes.isEmpty ? "Vigilando" : partes.joined(separator: " · ")
}

private func corto(_ e: AvisoAtributos.ContentState) -> String {
    if let media = e.media { return "⌀\(media)" }
    if let d = e.distancia { return distancia(d) }
    return e.kmh.map { "\($0)" } ?? ""
}

private struct Icono: View {
    let estado: AvisoAtributos.ContentState
    var body: some View {
        Image(systemName: estado.titulo == nil ? "checkmark.circle" : "camera.metering.center.weighted")
            .foregroundColor(estado.titulo == nil ? .green : Color(red: 1, green: 0.33, blue: 0.21))
    }
}

private struct Limite: View {
    let valor: Int
    let tamano: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(.white)
            Circle().strokeBorder(.red, lineWidth: tamano * 0.11)
            Text("\(valor)").font(.system(size: tamano * 0.38, weight: .bold)).foregroundColor(.black)
        }
        .frame(width: tamano, height: tamano)
    }
}

private struct Bloqueo: View {
    let estado: AvisoAtributos.ContentState
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Icono(estado: estado)
                    Text(estado.titulo ?? "Chivato vigilando").font(.headline).foregroundColor(.white)
                }
                Text(detalle(estado))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                if let kmh = estado.kmh {
                    Text("Vas a \(kmh) km/h").font(.subheadline).foregroundColor(.white.opacity(0.75))
                }
            }
            Spacer()
            if let limite = estado.limite { Limite(valor: limite, tamano: 58) }
        }
    }
}
