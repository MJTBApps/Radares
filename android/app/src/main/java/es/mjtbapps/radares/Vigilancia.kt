package es.mjtbapps.radares

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import es.mjtbapps.radares.nucleo.Evento
import es.mjtbapps.radares.nucleo.Frases
import es.mjtbapps.radares.nucleo.Geo
import es.mjtbapps.radares.nucleo.LectorIncidenciasDGT
import es.mjtbapps.radares.nucleo.MotorAvisos
import es.mjtbapps.radares.nucleo.MotorIncidencias
import es.mjtbapps.radares.nucleo.Posicion
import es.mjtbapps.radares.nucleo.TipoRadar
import kotlinx.coroutines.flow.update
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.GZIPInputStream
import kotlin.concurrent.thread

/**
 * Servicio en primer plano que vigila mientras se conduce: lee el GPS, decide los avisos,
 * los dice y mantiene una notificación con el próximo radar (se ve en la pantalla de bloqueo).
 */
class Vigilancia : Service(), LocationListener {
    private lateinit var ajustes: Ajustes
    private lateinit var voz: Voz
    private lateinit var motor: MotorAvisos
    private val incidencias = MotorIncidencias()
    private val hilo = Handler(Looper.getMainLooper())
    private var generado = ""
    private var total = 0
    private var alta: Boolean? = null
    private var ultimoMovimiento = System.currentTimeMillis()
    private var arrancadaSola = false
    private var ultimaNotificacion = 0L
    private var textoNotificacion = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ajustes = Ajustes(this)
        voz = Voz(this)
        val base = Base.cargar(this)
        motor = MotorAvisos(base.radares)
        generado = base.generado
        total = base.radares.size
        crearCanal(this)
    }

    @SuppressLint("MissingPermission")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == PARAR) { detener(); return START_NOT_STICKY }
        arrancadaSola = intent?.getBooleanExtra(SOLA, false) ?: false
        val n = notificacion("Vigilando $total radares")
        if (Build.VERSION.SDK_INT >= 29) startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        else startForeground(ID, n)
        if (!tienePermiso(this)) { Estado.anotar("Sin permiso de ubicación."); detener(); return START_NOT_STICKY }

        voz.salida = salidaEfectiva()
        voz.voz = "sistema"
        precision(true)
        Estado.pantalla.update { it.copy(activo = true) }
        Estado.anotar(if (arrancadaSola) "En coche: empiezo a vigilar $total radares." else "Vigilando $total radares.")
        hilo.post(vigilante)
        if (ajustes.avisosDGT) hilo.post(consultaDGT)
        thread {
            Base.actualizar(this, generado)?.let { nueva ->
                hilo.post {
                    motor.cambiar(nueva.radares); generado = nueva.generado; total = nueva.radares.size
                    Estado.anotar("Radares actualizados: $total (${nueva.generado}).")
                }
            }
        }
        return START_STICKY
    }

    private fun salidaEfectiva(): Salida {
        val s = ajustes.salida
        if (s == Salida.LLAMADA && !ajustes.llamadaDisponible) return Salida.ALTAVOZ
        return s
    }

    @SuppressLint("MissingPermission")
    private fun precision(fina: Boolean) {
        if (alta == fina) return
        alta = fina
        val lm = getSystemService(LocationManager::class.java)
        lm.removeUpdates(this)
        // Con un radar cerca, una lectura por segundo; si no, cada 5 s o 100 m.
        lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, if (fina) 1_000L else 5_000L, if (fina) 0f else 100f, this, Looper.getMainLooper())
        Estado.pantalla.update { it.copy(ahorro = !fina) }
    }

    override fun onLocationChanged(l: Location) {
        val p = Posicion(
            lat = l.latitude, lon = l.longitude,
            velocidad = if (l.hasSpeed()) l.speed.toDouble() else -1.0,
            rumbo = if (l.hasBearing() && l.hasSpeed() && l.speed > 1) l.bearing.toDouble() else -1.0,
            precision = if (l.hasAccuracy()) l.accuracy.toDouble() else 999.0,
            instante = l.time / 1000.0,
        )
        if (p.velocidad >= 3) ultimoMovimiento = System.currentTimeMillis()
        voz.salida = salidaEfectiva()
        voz.voz = "sistema"
        for (e in motor.procesar(p) + incidencias.procesar(p)) {
            val frase = Frases.texto(e)
            voz.decir(frase, Frases.piezas(e))
            Estado.anotar(frase)
        }
        val cercaIncidencia = incidencias.incidencias.any { Geo.distancia(p.lat, p.lon, it.lat, it.lon) < 6_000 }
        precision(motor.necesitaPrecision || cercaIncidencia)

        val t = motor.tramo
        val prox = motor.proximo
        val estado = when {
            t != null && t.dentro -> Estado.pantalla.value.copy(titulo = "Dentro de un tramo", media = t.media, limite = t.radar.limite,
                via = t.radar.via, distancia = t.restante)
            prox != null -> Estado.pantalla.value.copy(titulo = if (prox.first.tipo == TipoRadar.TRAMO) "Radar de tramo" else "Radar",
                distancia = prox.second, limite = prox.first.limite, via = prox.first.via, media = null)
            else -> Estado.pantalla.value.copy(titulo = null, distancia = null, limite = null, via = null, media = null)
        }
        Estado.pantalla.value = estado.copy(kmh = if (p.velocidad >= 0) p.kmh else null)
        actualizarNotificacion(estado)
    }

    private fun actualizarNotificacion(e: Pantalla) {
        val texto = when {
            e.media != null -> "Tramo: media ${e.media}" + (e.limite?.let { " · límite $it" } ?: "")
            e.titulo != null && e.distancia != null -> "${e.titulo} a ${Frases.distancia(e.distancia)}" +
                (e.limite?.let { " · límite $it" } ?: "") + (e.via?.let { " · $it" } ?: "")
            else -> "Vigilando · ningún radar delante"
        }
        val ahora = System.currentTimeMillis()
        if (texto == textoNotificacion || ahora - ultimaNotificacion < 3_000 && texto.startsWith(textoNotificacion.take(6))) return
        textoNotificacion = texto
        ultimaNotificacion = ahora
        getSystemService(NotificationManager::class.java).notify(ID, notificacion(texto))
    }

    private val vigilante = object : Runnable {
        override fun run() {
            val minutos = if (arrancadaSola) 5 else 15
            if (System.currentTimeMillis() - ultimoMovimiento > minutos * 60_000L) {
                Estado.anotar("Parado $minutos minutos sin moverte: GPS apagado.")
                detener()
                return
            }
            hilo.postDelayed(this, 60_000)
        }
    }

    private val consultaDGT = object : Runnable {
        override fun run() {
            if (!ajustes.avisosDGT) return
            thread {
                try {
                    val con = URL(LectorIncidenciasDGT.DIRECCION).openConnection() as HttpURLConnection
                    con.connectTimeout = 20_000; con.readTimeout = 40_000
                    con.setRequestProperty("Accept-Encoding", "gzip")
                    val entrada = if (con.contentEncoding == "gzip") GZIPInputStream(con.inputStream) else con.inputStream
                    val lista = entrada.use { LectorIncidenciasDGT.leer(it) }
                    hilo.post {
                        incidencias.cambiar(lista)
                        Estado.pantalla.update { it.copy(incidencias = lista.size) }
                    }
                } catch (e: Exception) {
                    Estado.anotar("DGT: sin conexión (${e.message}).")
                }
            }
            hilo.postDelayed(this, 5 * 60_000L)
        }
    }

    private fun detener() {
        hilo.removeCallbacksAndMessages(null)
        getSystemService(LocationManager::class.java).removeUpdates(this)
        Estado.pantalla.update { Pantalla(diario = it.diario) }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        hilo.removeCallbacksAndMessages(null)
        getSystemService(LocationManager::class.java).removeUpdates(this)
        voz.apagar()
        Estado.pantalla.update { it.copy(activo = false) }
        super.onDestroy()
    }

    private fun notificacion(texto: String): Notification {
        val abrir = PendingIntent.getActivity(this, 0, Intent(this, Principal::class.java), PendingIntent.FLAG_IMMUTABLE)
        val parar = PendingIntent.getService(this, 1, Intent(this, Vigilancia::class.java).setAction(PARAR), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CANAL)
            .setSmallIcon(R.drawable.ic_aviso)
            .setContentTitle("Chivato Radar")
            .setContentText(texto)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setContentIntent(abrir)
            .addAction(0, "Parar", parar)
            .build()
    }

    companion object {
        const val CANAL = "vigilancia"
        const val ID = 1
        const val PARAR = "parar"
        const val SOLA = "sola"

        fun crearCanal(c: Context) {
            val canal = NotificationChannel(CANAL, "Vigilando radares", NotificationManager.IMPORTANCE_LOW)
            canal.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            c.getSystemService(NotificationManager::class.java).createNotificationChannel(canal)
        }

        fun tienePermiso(c: Context) =
            ContextCompat.checkSelfPermission(c, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

        fun empezar(c: Context, sola: Boolean = false) {
            ContextCompat.startForegroundService(c, Intent(c, Vigilancia::class.java).putExtra(SOLA, sola))
        }

        fun parar(c: Context) {
            c.startService(Intent(c, Vigilancia::class.java).setAction(PARAR))
        }
    }
}
