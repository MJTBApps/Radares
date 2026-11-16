// Núcleo de Chivato Radar: modelos, geometría y motor de avisos de radares.
// Es una copia en Kotlin de ios/RadaresCore (Swift): si cambia uno, hay que cambiar el otro.
package es.mjtbapps.radares.nucleo

import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

enum class TipoRadar { FIJO, TRAMO }

data class Radar(
    val id: String,
    val lat: Double,
    val lon: Double,
    val tipo: TipoRadar = TipoRadar.FIJO,
    val limite: Int? = null,
    val via: String? = null,
    /** Sentido que vigila (grados desde el norte). null = cualquiera. */
    val rumbo: Double? = null,
    val finLat: Double? = null,
    val finLon: Double? = null,
    val longitud: Double? = null,
)

data class BaseRadares(val generado: String, val radares: List<Radar>) {
    companion object {
        fun leer(texto: String): BaseRadares {
            val o = JSONObject(texto)
            val lista = o.getJSONArray("radares")
            val radares = ArrayList<Radar>(lista.length())
            for (i in 0 until lista.length()) {
                val r = lista.getJSONObject(i)
                fun num(k: String) = if (r.has(k)) r.getDouble(k) else null
                radares += Radar(
                    id = r.getString("id"),
                    lat = r.getDouble("lat"),
                    lon = r.getDouble("lon"),
                    tipo = if (r.optString("tipo") == "tramo") TipoRadar.TRAMO else TipoRadar.FIJO,
                    limite = if (r.has("limite")) r.getInt("limite") else null,
                    via = if (r.has("via")) r.getString("via") else null,
                    rumbo = num("rumbo"),
                    finLat = num("finLat"),
                    finLon = num("finLon"),
                    longitud = num("longitud"),
                )
            }
            return BaseRadares(o.getString("generado"), radares)
        }
    }
}

/** Una lectura del GPS. velocidad en m/s (negativa = desconocida); rumbo en grados (negativo = desconocido). */
data class Posicion(
    val lat: Double,
    val lon: Double,
    val velocidad: Double,
    val rumbo: Double,
    val precision: Double,
    /** Segundos. */
    val instante: Double,
) {
    val kmh: Int get() = if (velocidad < 0) 0 else (velocidad * 3.6).roundToInt()
}

object Geo {
    private const val RADIO = 6_371_000.0

    fun distancia(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val f1 = Math.toRadians(lat1); val f2 = Math.toRadians(lat2)
        val df = f2 - f1; val dl = Math.toRadians(lon2 - lon1)
        val a = sin(df / 2) * sin(df / 2) + cos(f1) * cos(f2) * sin(dl / 2) * sin(dl / 2)
        return 2 * RADIO * asin(min(1.0, sqrt(a)))
    }

    fun rumbo(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val f1 = Math.toRadians(lat1); val f2 = Math.toRadians(lat2)
        val dl = Math.toRadians(lon2 - lon1)
        val y = sin(dl) * cos(f2)
        val x = cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dl)
        val g = Math.toDegrees(atan2(y, x))
        return if (g < 0) g + 360 else g
    }

    /** Diferencia entre rumbos, de -180 a 180. */
    fun diferencia(a: Double, b: Double): Double {
        var d = (b - a) % 360
        if (d > 180) d -= 360
        if (d < -180) d += 360
        return d
    }

    fun avanzar(lat: Double, lon: Double, rumbo: Double, metros: Double): Pair<Double, Double> {
        val d = metros / RADIO; val r = Math.toRadians(rumbo)
        val f1 = Math.toRadians(lat); val l1 = Math.toRadians(lon)
        val f2 = asin(sin(f1) * cos(d) + cos(f1) * sin(d) * cos(r))
        val l2 = l1 + atan2(sin(r) * sin(d) * cos(f1), cos(d) - sin(f1) * sin(f2))
        return Math.toDegrees(f2) to Math.toDegrees(l2)
    }
}

/** Radares repartidos en una rejilla de unos 5 km para no recorrer toda la lista en cada lectura. */
class IndiceRadares(val radares: List<Radar>) {
    private val paso = 0.05
    private val celdas = HashMap<Long, MutableList<Int>>()

    init {
        radares.forEachIndexed { i, r -> celdas.getOrPut(clave(fila(r.lat), fila(r.lon))) { mutableListOf() } += i }
    }

    private fun fila(g: Double) = Math.floor(g / paso).toInt()
    private fun clave(a: Int, b: Int) = a.toLong() * 100_000 + b

    fun cercanos(lat: Double, lon: Double, radio: Double): List<Pair<Radar, Double>> {
        val dLat = radio / 111_000
        val dLon = radio / (111_000 * max(0.2, cos(Math.toRadians(lat))))
        val salida = ArrayList<Pair<Radar, Double>>()
        for (a in fila(lat - dLat)..fila(lat + dLat)) for (b in fila(lon - dLon)..fila(lon + dLon)) {
            celdas[clave(a, b)]?.forEach { i ->
                val r = radares[i]
                val d = Geo.distancia(lat, lon, r.lat, r.lon)
                if (d <= radio) salida += r to d
            }
        }
        return salida.sortedBy { it.second }
    }
}

sealed class Evento {
    data class Radar(val radar: es.mjtbapps.radares.nucleo.Radar, val distancia: Double, val velocidad: Int) : Evento()
    data class ExcesoTramo(val radar: es.mjtbapps.radares.nucleo.Radar, val media: Int) : Evento()
    data class FinTramo(val radar: es.mjtbapps.radares.nucleo.Radar, val media: Int) : Evento()
    data class Incidencia(val incidencia: es.mjtbapps.radares.nucleo.Incidencia, val distancia: Double) : Evento()
}

class EstadoTramo(val radar: Radar) {
    var dentro = false
    var recorrido = 0.0
    var tiempo = 0.0
    internal var menorDistancia = Double.MAX_VALUE
    internal var ultima: Posicion? = null
    internal var excesoAvisado = false

    val media: Int? get() = if (!dentro || tiempo < 5 || recorrido < 100) null else (recorrido / tiempo * 3.6).roundToInt()
    val restante: Double? get() = if (!dentro) null else radar.longitud?.let { max(0.0, it - recorrido) }
}

/** Decide cuándo avisar de los radares. Igual que MotorAvisos.swift. */
class MotorAvisos(radares: List<Radar>) {
    var segundosAntelacion = 20.0
    var distanciaMinima = 400.0
    var distanciaMaxima = 1000.0
    var velocidadMinima = 4.0
    var rearme = 1500.0
    var precisionMaxima = 100.0
    var margenTramo = 2

    var indice = IndiceRadares(radares); private set
    var proximo: Pair<Radar, Double>? = null; private set
    var tramo: EstadoTramo? = null; private set
    var distanciaMasCercano: Double? = null; private set
    private val avisados = HashMap<String, Radar>()

    fun cambiar(radares: List<Radar>) { indice = IndiceRadares(radares); reiniciar() }

    fun reiniciar() { avisados.clear(); proximo = null; tramo = null; distanciaMasCercano = null }

    val necesitaPrecision: Boolean get() = tramo != null || (distanciaMasCercano?.let { it < 10_000 } ?: false)

    fun distanciaDeAviso(velocidad: Double) = min(distanciaMaxima, max(distanciaMinima, velocidad * segundosAntelacion))

    fun delante(r: Radar, p: Posicion, d: Double): Boolean {
        val giro = Math.toRadians(Geo.diferencia(p.rumbo, Geo.rumbo(p.lat, p.lon, r.lat, r.lon)))
        val avance = d * cos(giro)
        val lateral = abs(d * sin(giro))
        if (avance <= 0 || lateral > max(70.0, 0.2 * d)) return false
        val sentido = r.rumbo
        if (sentido != null && abs(Geo.diferencia(p.rumbo, sentido)) > 60) return false
        return true
    }

    fun procesar(p: Posicion): List<Evento> {
        val eventos = ArrayList<Evento>()
        distanciaMasCercano = indice.cercanos(p.lat, p.lon, 15_000.0).firstOrNull()?.second
        avisados.entries.removeAll { Geo.distancia(p.lat, p.lon, it.value.lat, it.value.lon) > rearme }
        eventos += seguirTramo(p)

        if (p.precision < 0 || p.precision > precisionMaxima || p.velocidad < velocidadMinima || p.rumbo < 0) {
            proximo = null
            return eventos
        }
        val aviso = distanciaDeAviso(p.velocidad)
        val candidatos = indice.cercanos(p.lat, p.lon, 2_500.0).filter { delante(it.first, p, it.second) }
        proximo = candidatos.firstOrNull()
        for ((r, d) in candidatos) {
            if (d > aviso || avisados.containsKey(r.id)) continue
            avisados[r.id] = r
            eventos += Evento.Radar(r, d, p.kmh)
            if (r.tipo == TipoRadar.TRAMO && tramo == null && (r.longitud != null || r.finLat != null)) {
                tramo = EstadoTramo(r)
            }
        }
        return eventos
    }

    private fun seguirTramo(p: Posicion): List<Evento> {
        val t = tramo ?: return emptyList()
        val r = t.radar
        val alInicio = Geo.distancia(p.lat, p.lon, r.lat, r.lon)
        if (!t.dentro) {
            t.menorDistancia = min(t.menorDistancia, alInicio)
            if (alInicio < 60 || (t.menorDistancia < 200 && alInicio > t.menorDistancia + 30)) {
                t.dentro = true
                t.ultima = p
            } else if (alInicio > t.menorDistancia + 600) {
                tramo = null
            }
            return emptyList()
        }
        val anterior = t.ultima ?: run { tramo = null; return emptyList() }
        val dt = p.instante - anterior.instante
        if (dt <= 0) return emptyList()
        if (dt > 30) { tramo = null; return emptyList() }
        t.recorrido += Geo.distancia(anterior.lat, anterior.lon, p.lat, p.lon)
        t.tiempo += dt
        t.ultima = p

        var fin = false
        val fLat = r.finLat; val fLon = r.finLon
        if (fLat != null && fLon != null) {
            val recta = Geo.distancia(r.lat, r.lon, fLat, fLon)
            if (Geo.distancia(p.lat, p.lon, fLat, fLon) < 80) fin = true
            if (t.recorrido > (r.longitud ?: (recta * 1.6 + 500)) * 1.15 + 300) { tramo = null; return emptyList() }
        } else if (r.longitud != null && t.recorrido >= r.longitud) {
            fin = true
        }
        if (fin) {
            tramo = null
            return t.media?.let { listOf(Evento.FinTramo(r, it)) } ?: emptyList()
        }
        val limite = r.limite
        val media = t.media
        if (!t.excesoAvisado && t.recorrido > 500 && limite != null && media != null && media > limite + margenTramo) {
            t.excesoAvisado = true
            return listOf(Evento.ExcesoTramo(r, media))
        }
        return emptyList()
    }
}

/** Frases de los avisos y piezas de audio de las voces grabadas. Igual que Frases en Swift. */
object Frases {
    val distancias: List<Int> = (50..900 step 50).toList() + (1_000..10_000 step 500).toList() + (11_000..50_000 step 1_000).toList()
    val velocidades = 10..250
    val limites: List<Int> = (10..130 step 5).toList()

    fun redondear(metros: Double): Int {
        val m = max(50.0, metros)
        val cerca = ((m / 50).roundToInt() * 50)
        if (cerca <= 900) return cerca
        val paso = if (m < 10_250) 500.0 else 1_000.0
        return min(max(((m / paso).roundToInt() * paso).toInt(), 1_000), 50_000)
    }

    fun decir(m: Int): String = when {
        m < 1_000 -> "$m metros"
        m == 1_000 -> "1 kilómetro"
        m % 1_000 == 0 -> "${m / 1_000} kilómetros"
        else -> "${m / 1_000},5 kilómetros"
    }

    fun distancia(metros: Double) = decir(redondear(metros))

    fun piezas(e: Evento): List<String>? { return when (e) {
        is Evento.Radar -> {
            val r = e.radar
            val p = mutableListOf("${if (r.tipo == TipoRadar.TRAMO) "tramo" else "radar"}_${redondear(e.distancia)}")
            if (r.tipo == TipoRadar.TRAMO && (r.longitud ?: 0.0) >= 500) p += "dura_${redondear(r.longitud!!)}"
            val limite = r.limite
            if (limite != null) {
                if (limite !in limites) return null
                p += "limite_$limite"
                if (e.velocidad > limite + 3) { if (e.velocidad !in velocidades) return null; p += "vas_${e.velocidad}" }
            }
            p
        }
        is Evento.ExcesoTramo -> {
            if (e.media !in velocidades) null else {
                val p = mutableListOf("media_${e.media}")
                val limite = e.radar.limite
                if (limite != null) { if (limite !in limites) return null; p += "limite_$limite" }
                p
            }
        }
        is Evento.FinTramo -> if (e.media in velocidades) listOf("fin_${e.media}") else null
        is Evento.Incidencia -> listOf("${e.incidencia.tipo.clave}_${redondear(e.distancia)}")
    } }

    fun texto(e: Evento): String = when (e) {
        is Evento.Radar -> {
            val r = e.radar
            var s = (if (r.tipo == TipoRadar.TRAMO) "Radar de tramo a " else "Radar a ") + distancia(e.distancia) + "."
            if (r.tipo == TipoRadar.TRAMO && (r.longitud ?: 0.0) >= 500) s += " Dura " + distancia(r.longitud!!) + "."
            r.limite?.let { l -> s += " Límite $l."; if (e.velocidad > l + 3) s += " Vas a ${e.velocidad}." }
            s
        }
        is Evento.ExcesoTramo -> "Media del tramo ${e.media}." + (e.radar.limite?.let { " Límite $it." } ?: "")
        is Evento.FinTramo -> "Fin del tramo. Media ${e.media}."
        is Evento.Incidencia -> "${e.incidencia.tipo.nombre} a ${distancia(e.distancia)}."
    }
}
