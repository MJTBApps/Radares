import Combine
import CoreLocation
import CoreMotion
import Foundation
import RadaresCore

/// Estado de la app: GPS, motores de avisos y voz. Todo ocurre en el hilo principal
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
    @Published private(set) var totalRadares = 0
    @Published private(set) var fechaDatos = "—"
    /// Incidencias de la DGT descargadas en la última consulta (nil = aún no se ha consultado).
    @Published private(set) var totalIncidencias: Int?

    @Published var salida: SalidaVoz {
        didSet {
            UserDefaults.standard.set(salida.rawValue, forKey: "salida")
            aplicarSalida()
        }
    }
    /// Voz elegida (ver `VozDisponible.id`); vacío = la voz por defecto del iPhone.
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
    /// Empezar sola al detectar que vamos en coche (necesita la ubicación «Siempre»).
    @Published var arranqueAutomatico: Bool {
        didSet {
            UserDefaults.standard.set(arranqueAutomatico, forKey: "arranqueAutomatico")
            configurarArranqueAutomatico(pedirPermiso: arranqueAutomatico)
        }
    }
    /// Avisar de accidentes, retenciones y obstáculos de la DGT (necesita datos móviles).
    @Published var avisosDGT: Bool {
        didSet {
            UserDefaults.standard.set(avisosDGT, forKey: "avisosDGT")
            if avisosDGT { if activo { consultarIncidencias() } } else { motorIncidencias.cambiar([]); totalIncidencias = nil }
        }
    }
    /// Tarjeta con el próximo radar en la pantalla de bloqueo y la isla dinámica.
    @Published var pantallaBloqueo: Bool {
        didSet {
            UserDefaults.standard.set(pantallaBloqueo, forKey: "pantallaBloqueo")
            if !pantallaBloqueo { actividad.terminar() } else if activo { actividad.empezar() }
        }
    }

    let voces = VozDisponible.grabadas() + VozDisponible.instaladas()

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
    private let movimiento = CMMotionActivityManager()
    private let motor: MotorAvisos
    private let motorIncidencias = MotorIncidencias()
    private let voz = Voz()
    private let actividad = ActividadAviso()
    private var quiereEmpezar = false
    private var ultimoMovimiento = Date()
    private var vigilante: Timer?
    private var relojIncidencias: Timer?
    /// Minutos parado tras los que la app deja de usar el GPS sola.
    private let minutosParado = 15.0
    /// Si ha empezado sola, se apaga antes al aparcar.
    private var arrancadaSola = false
    /// Comprobando si vamos en coche tras un aviso de «cambio significativo» de posición.
    private var comprobandoDesde: Date?
    /// Tras pulsar «Parar» no vuelve a arrancar sola durante un rato.
    private var sinArranqueHasta = Date.distantPast

    // MARK: - Base de radares

    /// Dirección de la base de radares actualizada (repositorio público MJTBApps/chivato-radar).
    static let direccionBase = URL(string: "https://mjtbapps.github.io/chivato-radar/radares.json")!
    private static var archivoBase: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("radares.json")
    }
    private var baseNueva: BaseRadares?

    override init() {
        let d = UserDefaults.standard
        salida = d.string(forKey: "salida").flatMap(SalidaVoz.init(rawValue:)) ?? .altavoz
        empezarAlAbrir = d.object(forKey: "empezarAlAbrir") as? Bool ?? true
        arranqueAutomatico = d.bool(forKey: "arranqueAutomatico")
        avisosDGT = d.object(forKey: "avisosDGT") as? Bool ?? true
        pantallaBloqueo = d.object(forKey: "pantallaBloqueo") as? Bool ?? true
        premium = d.bool(forKey: "premium")
        if let fecha = d.object(forKey: "primerUso") as? Date {
            primerUso = fecha
        } else {
            primerUso = Date()
            d.set(primerUso, forKey: "primerUso")
        }
        // Por defecto, la primera voz natural si la hay.
        idVoz = d.string(forKey: "idVoz") ?? (VozDisponible.grabadas().first?.id ?? "")

        // La base más reciente: la que viene con la app o la descargada.
        var errorDatos: String?
        var base: BaseRadares?
        if let url = Bundle.main.url(forResource: "radares", withExtension: "json") {
            do { base = try BaseRadares.leer(Data(contentsOf: url)) } catch { errorDatos = "\(error)" }
        }
        if let datos = try? Data(contentsOf: Modelo.archivoBase), let descargada = try? BaseRadares.leer(datos),
           descargada.generado > (base?.generado ?? "") {
            base = descargada
        }
        if base == nil, errorDatos == nil { errorDatos = "falta radares.json" }
        motor = MotorAvisos(radares: base?.radares ?? [])
        super.init()
        totalRadares = base?.radares.count ?? 0
        fechaDatos = base?.generado ?? "—"

        voz.idVoz = idVoz.isEmpty ? nil : idVoz
        aplicarSalida()
        voz.alFallar = { [weak self] texto in self?.anotar(texto) }
        gestor.delegate = self
        gestor.activityType = .automotiveNavigation
        gestor.pausesLocationUpdatesAutomatically = false
        permiso = gestor.authorizationStatus
        if let errorDatos { anotar("No se han podido leer los radares: \(errorDatos)") }
        configurarArranqueAutomatico(pedirPermiso: false)
        actividad.terminarHuerfanas()
        if empezarAlAbrir { empezar() }
        actualizarBase()
    }

    /// Descarga la base de radares nueva una vez al día como mucho.
    func actualizarBase(forzar: Bool = false) {
        let d = UserDefaults.standard
        if !forzar, let ultima = d.object(forKey: "ultimaConsultaBase") as? Date,
           Date().timeIntervalSince(ultima) < 86_400 { return }
        d.set(Date(), forKey: "ultimaConsultaBase")
        var peticion = URLRequest(url: Modelo.direccionBase)
        peticion.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: peticion) { [weak self] datos, respuesta, _ in
            guard let datos, (respuesta as? HTTPURLResponse)?.statusCode == 200,
                  let base = try? BaseRadares.leer(datos), base.radares.count >= 2_000 else { return }
            DispatchQueue.main.async {
                guard let self, base.generado > (self.fechaDatos == "—" ? "" : self.fechaDatos) else { return }
                try? datos.write(to: Modelo.archivoBase, options: .atomic)
                self.baseNueva = base
                if !self.activo { self.aplicarBaseNueva() }
            }
        }.resume()
    }

    private func aplicarBaseNueva() {
        guard let base = baseNueva else { return }
        baseNueva = nil
        motor.cambiar(radares: base.radares)
        totalRadares = base.radares.count
        fechaDatos = base.generado
        anotar("Radares actualizados: \(base.radares.count) (\(base.generado)).")
    }

    // MARK: - Empezar y parar

    func empezar(sola: Bool = false) {
        switch gestor.authorizationStatus {
        case .notDetermined:
            quiereEmpezar = true
            gestor.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            guard !activo else { return }
            // Con la app en uso al empezar (o con permiso «Siempre»), iOS deja seguir recibiendo
            // la posición con la pantalla apagada o en otra app (franja azul arriba).
            gestor.allowsBackgroundLocationUpdates = true
            gestor.showsBackgroundLocationIndicator = true
            motor.reiniciar()
            motorIncidencias.reiniciar()
            ponerPrecision(alta: true)
            gestor.startUpdatingLocation()
            activo = true
            arrancadaSola = sola
            comprobandoDesde = nil
            ultimoMovimiento = Date()
            vigilante?.invalidate()
            vigilante = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.pararSiLlevaParado()
            }
            if avisosDGT {
                consultarIncidencias()
                relojIncidencias?.invalidate()
                relojIncidencias = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                    self?.consultarIncidencias()
                }
            }
            if pantallaBloqueo { actividad.empezar() }
            anotar(sola ? "En coche: empiezo a vigilar \(totalRadares) radares." : "Vigilando \(totalRadares) radares.")
        default:
            anotar("Sin permiso de ubicación: actívalo en Ajustes.")
        }
    }

    /// `manual` = el usuario ha pulsado «Parar»: no arrancar sola en un rato aunque siga en el coche.
    func parar(manual: Bool = false) {
        guard activo else { return }
        if manual { sinArranqueHasta = Date().addingTimeInterval(30 * 60) }
        gestor.stopUpdatingLocation()
        // Con el arranque automático hay que seguir oyendo los cambios grandes de posición.
        gestor.allowsBackgroundLocationUpdates = arranqueAutomatico && permiso == .authorizedAlways
        vigilante?.invalidate()
        vigilante = nil
        relojIncidencias?.invalidate()
        relojIncidencias = nil
        activo = false
        kmh = nil
        proximo = nil
        distanciaProximo = nil
        tramo = nil
        ahorro = false
        actividad.terminar()
        aplicarBaseNueva()
    }

    private func pararSiLlevaParado() {
        let minutos = arrancadaSola ? 5 : minutosParado
        guard activo, Date().timeIntervalSince(ultimoMovimiento) > minutos * 60 else { return }
        parar()
        anotar("Parado \(Int(minutos)) minutos sin moverte: GPS apagado.")
    }

    /// El GPS a máxima precisión es casi todo el consumo: solo se pide con un radar a menos de 10 km.
    private func ponerPrecision(alta: Bool) {
        gestor.desiredAccuracy = alta ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        gestor.distanceFilter = alta ? kCLDistanceFilterNone : 300
        ahorro = !alta
    }

    // MARK: - Arranque automático

    /// iOS despierta la app (aunque esté cerrada) cuando la posición cambia unos cientos de metros,
    /// algo que sabe por las antenas y el wifi, sin GPS. Entonces se pregunta al sensor de movimiento
    /// si vamos en coche (casi no gasta); solo si lo confirma se enciende el GPS y empieza a vigilar.
    private func configurarArranqueAutomatico(pedirPermiso: Bool) {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        if arranqueAutomatico {
            if gestor.authorizationStatus == .authorizedAlways {
                gestor.allowsBackgroundLocationUpdates = true
                gestor.startMonitoringSignificantLocationChanges()
            } else if pedirPermiso {
                // iOS pregunta si se pasa a «Siempre». Si ya se denegó, hay que ir a Ajustes.
                gestor.requestAlwaysAuthorization()
            }
            // Pedir también el permiso de «Movimiento y forma física» (sale la pregunta la primera vez).
            if pedirPermiso, CMMotionActivityManager.isActivityAvailable() {
                movimiento.queryActivityStarting(from: Date().addingTimeInterval(-60), to: Date(), to: .main) { _, _ in }
            }
        } else {
            gestor.stopMonitoringSignificantLocationChanges()
            if !activo { gestor.allowsBackgroundLocationUpdates = false }
        }
    }

    private func comprobarSiConduce(_ l: CLLocation) {
        guard arranqueAutomatico, !activo, comprobandoDesde == nil, Date() > sinArranqueHasta else { return }
        guard CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() != .denied else {
            // Sin sensor de movimiento: la velocidad que traiga el aviso, si la trae.
            if l.speed >= 7 { empezar(sola: true) }
            return
        }
        comprobandoDesde = Date()
        // Lo que ha detectado el sensor en los últimos 3 minutos.
        movimiento.queryActivityStarting(from: Date().addingTimeInterval(-180), to: Date(), to: .main) { [weak self] lista, _ in
            guard let self else { return }
            self.comprobandoDesde = nil
            let ultima = lista?.last { $0.confidence != .low }
            if let ultima, ultima.automotive, !ultima.walking, !ultima.running, !ultima.cycling {
                self.empezar(sola: true)
            }
        }
    }

    // MARK: - Incidencias de la DGT

    private func consultarIncidencias() {
        guard avisosDGT else { return }
        var peticion = URLRequest(url: LectorIncidenciasDGT.direccion)
        peticion.timeoutInterval = 40
        URLSession.shared.dataTask(with: peticion) { [weak self] datos, respuesta, error in
            guard let datos, (respuesta as? HTTPURLResponse)?.statusCode == 200 else {
                DispatchQueue.main.async {
                    self?.anotar("DGT: sin conexión (\(error?.localizedDescription ?? "error del servidor")).")
                }
                return
            }
            let lista = LectorIncidenciasDGT.leer(datos)
            DispatchQueue.main.async {
                guard let self, self.avisosDGT else { return }
                self.motorIncidencias.cambiar(lista)
                self.totalIncidencias = lista.count
            }
        }.resume()
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

    private func decir(_ frase: String, piezas: [String]? = nil) {
        aplicarSalida()   // la prueba puede terminar en mitad de un viaje
        voz.decir(frase, piezas: piezas)
    }

    func probarSonido(dentroDe segundos: Double = 0) {
        let frase = "Prueba. Radar a 500 metros. Límite 120."
        let piezas = ["prueba", "radar_500", "limite_120"]
        if segundos <= 0 {
            decir(frase, piezas: piezas)
        } else {
            anotar("Prueba de sonido en \(Int(segundos)) segundos.")
            DispatchQueue.main.asyncAfter(deadline: .now() + segundos) { [weak self] in
                self?.decir(frase, piezas: piezas)
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
        if arranqueAutomatico, permiso == .authorizedAlways { configurarArranqueAutomatico(pedirPermiso: false) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        guard activo else { comprobarSiConduce(l); return }
        let p = Posicion(lat: l.coordinate.latitude, lon: l.coordinate.longitude,
                         velocidad: l.speed, rumbo: l.course, precision: l.horizontalAccuracy,
                         instante: l.timestamp.timeIntervalSince1970)
        if l.speed >= 3 { ultimoMovimiento = Date() }

        for evento in motor.procesar(p) + motorIncidencias.procesar(p) {
            let frase = Frases.texto(evento)
            decir(frase, piezas: Frases.piezas(evento))
            anotar(frase)
        }

        kmh = l.speed >= 0 ? p.kmh : nil
        proximo = motor.proximo?.radar
        distanciaProximo = motor.proximo?.distancia
        tramo = motor.tramo
        // Con incidencias de la DGT cerca también hace falta el GPS fino (rumbo fiable).
        let incidenciaCerca = motorIncidencias.incidencias.contains {
            Geo.distancia(p.lat, p.lon, $0.lat, $0.lon) < 6_000
        }
        let alta = motor.necesitaPrecision || incidenciaCerca
        if alta == ahorro { ponerPrecision(alta: alta) }
        if pantallaBloqueo {
            actividad.actualizar(kmh: kmh, radar: proximo, distancia: distanciaProximo, tramo: tramo)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // «Ubicación desconocida» es pasajero (túneles): el gestor sigue intentándolo solo.
        if (error as? CLError)?.code == .locationUnknown { return }
        anotar("GPS: \(error.localizedDescription)")
    }
}
