// Incidencias de tráfico de la DGT en directo. Igual que Incidencias.swift.
package es.mjtbapps.radares.nucleo

import org.xml.sax.Attributes
import org.xml.sax.helpers.DefaultHandler
import java.io.InputStream
import java.time.OffsetDateTime
import javax.xml.parsers.SAXParserFactory
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

enum class TipoIncidencia(val clave: String, val nombre: String, val horasValidez: Double) {
    ACCIDENTE("accidente", "Accidente", 12.0),
    VEHICULO("vehiculo", "Vehículo detenido", 12.0),
    OBSTACULO("obstaculo", "Obstáculo en la calzada", 24.0),
    RETENCION("retencion", "Retención", 6.0),
    METEO("meteo", "Tiempo adverso", 24.0),
}

data class Incidencia(
    val id: String,
    val tipo: TipoIncidencia,
    val lat: Double,
    val lon: Double,
    val rumbo: Double? = null,
    val via: String? = null,
    /** Segundos desde 1970. */
    val inicio: Double? = null,
)

object LectorIncidenciasDGT {
    const val DIRECCION = "https://nap.dgt.es/datex2/v3/dgt/SituationPublication/datex2_v37.xml"

    /** `ahora` en segundos desde 1970. */
    fun leer(datos: InputStream, ahora: Double = System.currentTimeMillis() / 1000.0): List<Incidencia> {
        val salida = ArrayList<Incidencia>()
        val manejador = object : DefaultHandler() {
            val texto = StringBuilder()
            val ruta = ArrayList<String>()
            var id = ""; var causa = ""; var inicio: Double? = null; var via: String? = null; var sentido = ""
            var desde: Pair<Double, Double>? = null; var hasta: Pair<Double, Double>? = null
            var lat: Double? = null; var lon: Double? = null

            fun local(n: String) = n.substringAfterLast(':')

            override fun startElement(uri: String?, localName: String?, qName: String, atts: Attributes) {
                val n = local(qName)
                ruta += n
                texto.setLength(0)
                if (n == "situationRecord") {
                    id = atts.getValue("id") ?: ""
                    causa = ""; inicio = null; via = null; sentido = ""; desde = null; hasta = null
                } else if (n == "pointCoordinates") { lat = null; lon = null }
            }

            override fun characters(ch: CharArray, start: Int, length: Int) { texto.append(ch, start, length) }

            override fun endElement(uri: String?, localName: String?, qName: String) {
                val n = local(qName)
                val v = texto.toString().trim()
                texto.setLength(0)
                when (n) {
                    "causeType" -> causa = v
                    "overallStartTime" -> inicio = runCatching { OffsetDateTime.parse(v).toEpochSecond().toDouble() }.getOrNull()
                    "roadName" -> via = v.ifEmpty { null }
                    "tpegDirection" -> sentido = v
                    "latitude" -> lat = v.toDoubleOrNull()
                    "longitude" -> lon = v.toDoubleOrNull()
                    "pointCoordinates" -> {
                        val la = lat; val lo = lon
                        if (la != null && lo != null) {
                            when (if (ruta.size >= 2) ruta[ruta.size - 2] else "") {
                                "from" -> desde = la to lo
                                "to" -> hasta = la to lo
                                else -> if (desde == null && hasta == null) desde = la to lo
                            }
                        }
                    }
                    "situationRecord" -> terminar()
                }
                ruta.removeAt(ruta.size - 1)
            }

            fun terminar() {
                val tipo = when (causa) {
                    "accident" -> TipoIncidencia.ACCIDENTE
                    "vehicleObstruction" -> TipoIncidencia.VEHICULO
                    "obstruction" -> TipoIncidencia.OBSTACULO
                    "abnormalTraffic" -> TipoIncidencia.RETENCION
                    "poorEnvironment" -> TipoIncidencia.METEO
                    else -> return
                }
                inicio?.let { if (ahora - it > tipo.horasValidez * 3600) return }
                val punto = desde ?: hasta ?: return
                var rumbo: Double? = null
                val d = desde; val h = hasta
                if (sentido != "unknown" && sentido != "bothWays" && d != null && h != null &&
                    Geo.distancia(d.first, d.second, h.first, h.second) > 30) {
                    rumbo = Geo.rumbo(d.first, d.second, h.first, h.second)
                }
                if (tipo == TipoIncidencia.VEHICULO && rumbo == null) return
                salida += Incidencia(id, tipo, punto.first, punto.second, rumbo, via, inicio)
            }
        }
        SAXParserFactory.newInstance().newSAXParser().parse(datos, manejador)
        return salida
    }
}

class MotorIncidencias {
    var distanciaAviso = 2_000.0
    var velocidadMinima = 8.0
    var incidencias: List<Incidencia> = emptyList(); private set
    private val avisadas = HashSet<String>()

    fun cambiar(nuevas: List<Incidencia>) {
        incidencias = nuevas
        avisadas.retainAll(nuevas.map { it.id }.toSet())
    }

    fun reiniciar() = avisadas.clear()

    fun procesar(p: Posicion): List<Evento> {
        if (p.velocidad < velocidadMinima || p.rumbo < 0 || p.precision < 0 || p.precision > 100) return emptyList()
        val eventos = ArrayList<Evento>()
        for (i in incidencias) {
            if (i.id in avisadas) continue
            val d = Geo.distancia(p.lat, p.lon, i.lat, i.lon)
            if (d > distanciaAviso || d < 150) continue
            val giro = Math.toRadians(Geo.diferencia(p.rumbo, Geo.rumbo(p.lat, p.lon, i.lat, i.lon)))
            if (d * cos(giro) <= 0 || abs(d * sin(giro)) > max(80.0, 0.15 * d)) continue
            val sentido = i.rumbo
            if (sentido != null && abs(Geo.diferencia(p.rumbo, sentido)) > 60) continue
            avisadas += i.id
            eventos += Evento.Incidencia(i, d)
        }
        return eventos
    }
}
