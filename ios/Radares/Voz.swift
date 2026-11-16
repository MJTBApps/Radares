import AVFoundation

/// Por dónde suena el aviso. El coche puede estar con su propia música (no en la
/// fuente Bluetooth), y entonces el sonido normal del iPhone no se oye en ningún sitio.
enum SalidaVoz: String, CaseIterable, Identifiable {
    case altavoz
    case llamada
    case multimedia

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .altavoz: return "Altavoz del iPhone"
        case .llamada: return "Coche, como llamada"
        case .multimedia: return "Bluetooth normal"
        }
    }

    var explicacion: String {
        switch self {
        case .altavoz:
            return "Suena por el altavoz del móvil aunque esté enlazado al coche. No toca la música del coche."
        case .llamada:
            return "Entra por el canal de llamadas: el coche baja su música y lo dice por sus altavoces, sin cambiar de fuente. Tarda un segundo más."
        case .multimedia:
            return "Como cualquier app de música: solo se oye si el coche está en la fuente Bluetooth (o por el móvil si no hay coche)."
        }
    }
}

/// Una voz para los avisos: grabada (audios que van con la app, generados con IA)
/// o una de las voces en castellano del iPhone.
struct VozDisponible: Identifiable, Equatable {
    /// «grabada:<carpeta>» o el identificador de la voz del iPhone.
    let id: String
    let titulo: String

    static let prefijoGrabada = "grabada:"
    var grabada: Bool { id.hasPrefix(Self.prefijoGrabada) }

    /// Carpeta con los audios de las voces grabadas (`Voces/<voz>/<pieza>.mp3`).
    static var carpetaVoces: URL? { Bundle.main.url(forResource: "Voces", withExtension: nil) }

    /// Nombres bonitos de las voces grabadas, por carpeta.
    private static let nombres = ["lucia": "Lucía", "pablo": "Pablo", "sara": "Sara", "dani": "Dani"]

    static func grabadas() -> [VozDisponible] {
        guard let carpeta = carpetaVoces,
              let lista = try? FileManager.default.contentsOfDirectory(atPath: carpeta.path) else { return [] }
        return lista.sorted().compactMap { nombre in
            var dir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: carpeta.appendingPathComponent(nombre).path, isDirectory: &dir),
                  dir.boolValue else { return nil }
            return VozDisponible(id: prefijoGrabada + nombre,
                                 titulo: (nombres[nombre] ?? nombre.capitalized) + " (natural)")
        }
    }

    /// Las voces en castellano del iPhone: primero las de España y, dentro de cada país, las de más calidad.
    static func instaladas() -> [VozDisponible] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("es") }
            .sorted { a, b in
                let ea = a.language == "es-ES", eb = b.language == "es-ES"
                if ea != eb { return ea }
                if a.language != b.language { return a.language < b.language }
                if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
            .map { VozDisponible(id: $0.identifier, titulo: titulo(de: $0)) }
    }

    private static func titulo(de voz: AVSpeechSynthesisVoice) -> String {
        let pais = voz.language.split(separator: "-").last.map(String.init) ?? ""
        let lugar = Locale(identifier: "es_ES").localizedString(forRegionCode: pais) ?? pais
        // 1 = normal, 2 = mejorada, 3 = premium (las dos últimas se descargan en Ajustes).
        let calidad = voz.quality.rawValue >= 3 ? ", premium" : (voz.quality.rawValue == 2 ? ", mejorada" : "")
        return "\(voz.name) (\(lugar)\(calidad))"
    }
}

final class Voz: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    var salida: SalidaVoz = .altavoz
    /// Voz elegida: «grabada:<carpeta>», el identificador de una voz del iPhone, o nil (la de por defecto).
    var idVoz: String?
    /// Recibe los errores de sonido para enseñarlos en el diario de la pantalla.
    var alFallar: ((String) -> Void)?

    private enum Frase {
        case texto(String)
        case audios([URL])
    }

    private let sintetizador = AVSpeechSynthesizer()
    private let sesion = AVAudioSession.sharedInstance()
    private var cola: [Frase] = []
    private var hablando = false
    private var reproductor: AVAudioPlayer?
    private var audiosPendientes: [URL] = []

    override init() {
        super.init()
        sintetizador.delegate = self
    }

    /// Dice un aviso. Con una voz grabada usa `piezas` (si están todas); si no, la voz del iPhone con `texto`.
    func decir(_ texto: String, piezas: [String]? = nil) {
        cola.append(audios(piezas).map(Frase.audios) ?? .texto(texto))
        guard !hablando else { return }
        hablando = true
        // El canal de llamadas del coche tarda en abrirse; sin esta espera se pierde el principio.
        let espera = abrirSesion() ? (salida == .llamada ? 1.2 : 0.1) : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + espera) { self.siguiente() }
    }

    /// URLs de los audios de la voz grabada elegida, o nil si falta alguno.
    private func audios(_ piezas: [String]?) -> [URL]? {
        guard let piezas, !piezas.isEmpty, let id = idVoz, id.hasPrefix(VozDisponible.prefijoGrabada),
              let carpeta = VozDisponible.carpetaVoces else { return nil }
        let dir = carpeta.appendingPathComponent(String(id.dropFirst(VozDisponible.prefijoGrabada.count)))
        let urls = piezas.map { dir.appendingPathComponent($0 + ".mp3") }
        return urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } ? urls : nil
    }

    /// Activa la sesión de audio. Devuelve false si ha tenido que pasar al modo normal.
    private func abrirSesion() -> Bool {
        do {
            try preparar(salida)
            try sesion.setActive(true)
            return true
        } catch {
            alFallar?("Sonido «\(salida.titulo)»: \(error.localizedDescription). Pruebo el modo normal.")
            do {
                try preparar(.multimedia)
                try sesion.setActive(true)
            } catch {
                alFallar?("Sonido normal: \(error.localizedDescription)")
            }
            return false
        }
    }

    private func siguiente() {
        guard !cola.isEmpty else { terminar(); return }
        switch cola.removeFirst() {
        case let .texto(texto):
            let frase = AVSpeechUtterance(string: texto)
            // Con una voz grabada que no tiene esta frase, o si la elegida se ha borrado, la de por defecto.
            let sistema = idVoz.flatMap { $0.hasPrefix(VozDisponible.prefijoGrabada) ? nil : AVSpeechSynthesisVoice(identifier: $0) }
            frase.voice = sistema ?? AVSpeechSynthesisVoice(language: "es-ES")
            frase.volume = 1
            sintetizador.speak(frase)
        case let .audios(urls):
            audiosPendientes = urls
            siguienteAudio()
        }
    }

    private func siguienteAudio() {
        guard !audiosPendientes.isEmpty else { siguiente(); return }
        let url = audiosPendientes.removeFirst()
        do {
            let r = try AVAudioPlayer(contentsOf: url)
            r.delegate = self
            r.volume = 1
            reproductor = r
            if !r.play() { siguienteAudio() }
        } catch {
            alFallar?("Audio \(url.lastPathComponent): \(error.localizedDescription)")
            siguienteAudio()
        }
    }

    private func terminar() {
        hablando = false
        reproductor = nil
        // Soltar la sesión: el coche cierra el canal de llamada y la música vuelve a su volumen.
        try? sesion.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.siguienteAudio() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.siguiente() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.siguiente() }
    }

    /// Todas las opciones llevan `duckOthers`: baja el sonido de otras apps del iPhone mientras
    /// habla y, al ser una sesión que se mezcla, iOS deja activarla con la app en segundo plano.
    private func preparar(_ modo: SalidaVoz) throws {
        switch modo {
        case .altavoz:
            // Sin opciones de Bluetooth, «reproducir y grabar» no sale por el coche: va al altavoz.
            try sesion.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        case .llamada:
            // `allowBluetooth` es el perfil de manos libres (HFP), el mismo de las llamadas.
            try sesion.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .duckOthers])
        case .multimedia:
            try sesion.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        }
    }
}
