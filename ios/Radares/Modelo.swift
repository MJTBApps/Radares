import Combine
import CoreLocation
import Foundation
import RadaresCore

/// Estado de la app: GPS, motor de avisos y voz. Todo ocurre en el hilo principal
/// (el gestor de ubicación se crea ahí y avisa ahí).
final class Modelo: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var activo = false
    @Published private(set) var permiso: CLAuthorizationStatus = .notDetermined
    @Published private(set) var kmh: Int?
    @Published private(set) var proximo: Radar?
    @Published private(set) var distanciaProximo: Double?
    @Published private(set) var tramo: EstadoTramo?
    /// true = GPS en precisión baja porque no hay radares cerca.
    @Published private(set) var ahorro = false
    @Published private(set) var diario: [String] = []

    @Published var salida: SalidaVoz {
        didSet {
            UserDefaults.standard.set(salida.rawValue, forKey: "salida")
            aplicarSalida()
        }
    }
    /// Identificador de la voz elegida; vacío = la voz por defecto del iPhone.
    @Published var idVoz: String {
        didSet {
            voz.idVoz = idVoz.isEmpty ? nil : idVoz
            UserDefaults.standard.set(idVoz, forKey: "idVoz")
        }
    }
    /// Lo último que dijo el App Store. Se guarda para no perder el modo coche si la app
    /// arranca sola y sin cobertura.
    @Published var premium: Bool {
        didSet {
            UserDefaults.standard.set(premium, forKey: "premium")
            aplicarSalida()
        }
    }
    @Published var empezarAlAbrir: Bool {
        didSet { UserDefaults.standard.set(empezarAlAbrir, forKey: "empezarAlAbrir") }
    }

    let totalRadares: Int
    let fechaDatos: String
    let voces = VozDisponible.instaladas()

    /// Días que el aviso por los altavoces del coche funciona sin Premium, desde el primer uso.
    static let diasDePrueba = 14
    private let primerUso: Date
    private var avisadoFinPrueba = false

    var diasDePruebaRestantes: Int {
        let pasados = Int(Date().timeIntervalSince(primerUso) / 86_400)
        return max(0, Modelo.diasDePrueba - pasados)
    }

    /// El modo «Coche, como llamada» es de Premium; los primeros días se puede probar gratis.
    var llamadaDisponible: Bool { premium || diasDePruebaRestantes > 0 }

    private let gestor = CLLocationManager()
    private let motor: MotorAvisos
    private let voz = Voz()
    private var quiereEmpezar = false
    private var ultimoMovimiento = Date()
    private var vigilante: Timer?
    /// Minutos parado tras los que la app deja de usar el GPS sola.
    private let minutosParado = 15.0

    override init() {
        let guardada = UserDefaults.standard.string(forKey: "salida").flatMap(SalidaVoz.init(rawValue:))
        salida = guardada ?? .altavoz
        empezarAlAbrir = UserDefaults.standard.object(forKey: "empezarAlAbrir") as? Bool ?? true
        idVoz = UserDefaults.standard.string(forKey: "idVoz") ?? ""
        premium = UserDefaults.standard.bool(forKey: "premium")
        if let fecha = UserDefaults.standard.object(forKey: "primerUso") as? Date {
            primerUso = fecha
        } else {
            primerUso = Date()
            UserDefaults.standard.set(primerUso, forKey: "primerUso")
        }

        var base: BaseRadares?
        var errorDatos: String?
        if let url = Bundle.main.url(forResource: "radares", withExtension: "json") {
            do { base = try BaseRadares.leer(Data(contentsOf: url)) } catch { errorDatos = "\(error)" }
        } else {
            errorDatos = "falta radares.json"
        }
        motor = MotorAvisos(radares: base?.radares ?? [])
        totalRadares = base?.radares.count ?? 0
        fechaDatos = base?.generado ?? "—"
        super.init()

        voz.idVoz = idVoz.isEmpty ? nil : idVoz
        aplicarSalida()
        voz.alFallar = { [weak self] texto in self?.anotar(texto) }
        gestor.delegate = self
        gestor.activityType = .automotiveNavigation
        gestor.pausesLocationUpdatesAutomatically = false
        permiso = gestor.authorizationStatus
        if let errorDatos { anotar("No se han podido leer los radares: \(errorDatos)") }
        if empezarAlAbrir { empezar() }
    }

    // MARK: - Empezar y parar

    func empezar() {
        switch gestor.authorizationStatus {
        case .notDetermined:
            quiereEmpezar = true
            gestor.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            guard !activo else { return }
            // Con la app en uso al empezar, iOS deja seguir recibiendo la posición con la
            // pantalla apagada o en otra app (modo «location» y franja azul arriba).
            gestor.allowsBackgroundLocationUpdates = true
            gestor.showsBackgroundLocationIndicator = true
            motor.reiniciar()
            ponerPrecision(alta: true)
            gestor.startUpdatingLocation()
            activo = true
            ultimoMovimiento = Date()
            vigilante?.invalidate()
            vigilante = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.pararSiLlevaParado()
            }
            anotar("Vigilando \(totalRadares) radares.")
        default:
            anotar("Sin permiso de ubicación: actívalo en Ajustes.")
        }
    }

    func parar() {
        guard activo else { return }
        gestor.stopUpdatingLocation()
        gestor.allowsBackgroundLocationUpdates = false
        vigilante?.invalidate()
        vigilante = nil
        activo = false
        kmh = nil
        proximo = nil
        distanciaProximo = nil
        tramo = nil
        ahorro = false
    }

    private func pararSiLlevaParado() {
        guard activo, Date().timeIntervalSince(ultimoMovimiento) > minutosParado * 60 else { return }
        parar()
        anotar("Parado \(Int(minutosParado)) minutos sin moverte: GPS apagado.")
    }

    /// El GPS a máxima precisión es casi todo el consumo: solo se pide con un radar a menos de 10 km.
    private func ponerPrecision(alta: Bool) {
        gestor.desiredAccuracy = alta ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        gestor.distanceFilter = alta ? kCLDistanceFilterNone : 300
        ahorro = !alta
    }

    // MARK: - Sonido

    /// Sin Premium y con la prueba terminada, el modo coche suena por el altavoz del iPhone.
    private func aplicarSalida() {
        if salida == .llamada && !llamadaDisponible {
            voz.salida = .altavoz
            if !avisadoFinPrueba {
                avisadoFinPrueba = true
                anotar("La prueba del aviso por el coche ha terminado: suena por el iPhone. Con Premium vuelve al coche.")
            }
        } else {
            voz.salida = salida
        }
    }

    private func decir(_ frase: String) {
        aplicarSalida()   // la prueba puede terminar en mitad de un viaje
        voz.decir(frase)
    }

    func probarSonido(dentroDe segundos: Double = 0) {
        let frase = "Prueba. Radar a 500 metros. Límite 120."
        if segundos <= 0 {
            decir(frase)
        } else {
            anotar("Prueba de sonido en \(Int(segundos)) segundos.")
            DispatchQueue.main.asyncAfter(deadline: .now() + segundos) { [weak self] in
                self?.decir(frase)
            }
        }
    }

    // MARK: - Diario

    private func anotar(_ texto: String) {
        let hora = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        diario.insert("\(hora)  \(texto)", at: 0)
        if diario.count > 30 { diario.removeLast(diario.count - 30) }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        permiso = manager.authorizationStatus
        if quiereEmpezar, permiso == .authorizedWhenInUse || permiso == .authorizedAlways {
            quiereEmpezar = false
            empezar()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard activo, let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        let p = Posicion(lat: l.coordinate.latitude, lon: l.coordinate.longitude,
                         velocidad: l.speed, rumbo: l.course, precision: l.horizontalAccuracy,
                         instante: l.timestamp.timeIntervalSince1970)
        if l.speed >= 3 { ultimoMovimiento = Date() }

        for evento in motor.procesar(p) {
            let frase = Frases.texto(evento)
            decir(frase)
            anotar(frase)
        }

        kmh = l.speed >= 0 ? p.kmh : nil
        proximo = motor.proximo?.radar
        distanciaProximo = motor.proximo?.distancia
        tramo = motor.tramo
        if motor.necesitaPrecision == ahorro { ponerPrecision(alta: motor.necesitaPrecision) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // «Ubicación desconocida» es pasajero (túneles): el gestor sigue intentándolo solo.
        if (error as? CLError)?.code == .locationUnknown { return }
        anotar("GPS: \(error.localizedDescription)")
    }
}
