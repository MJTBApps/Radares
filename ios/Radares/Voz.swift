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

final class Voz: NSObject, AVSpeechSynthesizerDelegate {
    var salida: SalidaVoz = .altavoz
    /// Recibe los errores de sonido para enseñarlos en el diario de la pantalla.
    var alFallar: ((String) -> Void)?

    private let sintetizador = AVSpeechSynthesizer()
    private let sesion = AVAudioSession.sharedInstance()
    private var pendientes = 0

    override init() {
        super.init()
        sintetizador.delegate = self
    }

    func decir(_ texto: String) {
        var espera = 0.1
        do {
            try preparar(salida)
            try sesion.setActive(true)
            // El canal de llamadas del coche tarda en abrirse; sin esta espera se pierde el principio.
            if salida == .llamada { espera = 1.2 }
        } catch {
            alFallar?("Sonido «\(salida.titulo)»: \(error.localizedDescription). Pruebo el modo normal.")
            do {
                try preparar(.multimedia)
                try sesion.setActive(true)
            } catch {
                alFallar?("Sonido normal: \(error.localizedDescription)")
            }
        }
        let frase = AVSpeechUtterance(string: texto)
        frase.voice = AVSpeechSynthesisVoice(language: "es-ES")
        frase.volume = 1
        frase.preUtteranceDelay = espera
        pendientes += 1
        sintetizador.speak(frase)
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

    private func terminar() {
        pendientes = max(0, pendientes - 1)
        guard pendientes == 0 else { return }
        // Soltar la sesión: el coche cierra el canal de llamada y la música vuelve a su volumen.
        try? sesion.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.terminar() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.terminar() }
    }
}
