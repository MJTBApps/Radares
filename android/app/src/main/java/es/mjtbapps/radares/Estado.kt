package es.mjtbapps.radares

import android.content.Context
import es.mjtbapps.radares.nucleo.BaseRadares
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.DateFormat
import java.util.Date

/** Cómo suena el aviso. Mismos tres modos que en el iPhone. */
enum class Salida(val titulo: String, val explicacion: String) {
    ALTAVOZ("Altavoz del móvil", "Suena por el altavoz del móvil aunque esté conectado al coche. No toca la música del coche."),
    LLAMADA("Coche, como llamada", "Entra por el canal de llamadas: el coche baja su música y lo dice por sus altavoces, sin cambiar de fuente. Tarda un segundo más."),
    MULTIMEDIA("Bluetooth normal", "Como cualquier app de música: solo se oye si el coche está en la fuente Bluetooth."),
}

/** Lo que enseña la pantalla. Lo escribe el servicio de vigilancia. */
data class Pantalla(
    val activo: Boolean = false,
    val kmh: Int? = null,
    val titulo: String? = null,
    val distancia: Double? = null,
    val limite: Int? = null,
    val via: String? = null,
    val media: Int? = null,
    val ahorro: Boolean = false,
    val incidencias: Int? = null,
    val diario: List<String> = emptyList(),
)

object Estado {
    val pantalla = MutableStateFlow(Pantalla())

    fun anotar(texto: String) {
        val hora = DateFormat.getTimeInstance(DateFormat.MEDIUM).format(Date())
        pantalla.update { it.copy(diario = (listOf("$hora  $texto") + it.diario).take(30)) }
    }
}

/** Preferencias guardadas en el móvil. */
class Ajustes(contexto: Context) {
    private val p = contexto.getSharedPreferences("ajustes", Context.MODE_PRIVATE)

    var salida: Salida
        get() = runCatching { Salida.valueOf(p.getString("salida", "ALTAVOZ")!!) }.getOrDefault(Salida.ALTAVOZ)
        set(v) = p.edit().putString("salida", v.name).apply()
    /** «grabada:<carpeta>» o «sistema». */
    var voz: String
        get() = p.getString("voz", "") ?: ""
        set(v) = p.edit().putString("voz", v).apply()
    var arranqueAutomatico: Boolean
        get() = p.getBoolean("arranqueAutomatico", false)
        set(v) = p.edit().putBoolean("arranqueAutomatico", v).apply()
    var avisosDGT: Boolean
        get() = p.getBoolean("avisosDGT", true)
        set(v) = p.edit().putBoolean("avisosDGT", v).apply()
    var premium: Boolean
        get() = p.getBoolean("premium", false)
        set(v) = p.edit().putBoolean("premium", v).apply()
    var ultimaConsultaBase: Long
        get() = p.getLong("ultimaConsultaBase", 0)
        set(v) = p.edit().putLong("ultimaConsultaBase", v).apply()
    val primerUso: Long
        get() {
            if (!p.contains("primerUso")) p.edit().putLong("primerUso", System.currentTimeMillis()).apply()
            return p.getLong("primerUso", System.currentTimeMillis())
        }

    val diasDePruebaRestantes: Int
        get() = maxOf(0, DIAS_PRUEBA - ((System.currentTimeMillis() - primerUso) / 86_400_000L).toInt())

    /** Lo de Premium (aviso por el coche y arranque automático), con 14 días de prueba. */
    val llamadaDisponible: Boolean get() = premium || diasDePruebaRestantes > 0

    companion object { const val DIAS_PRUEBA = 14 }
}

/** Base de radares: la de la app o la descargada, la más reciente. */
object Base {
    const val DIRECCION = "https://mjtbapps.github.io/chivato-radar/radares.json"

    private fun archivo(c: Context) = File(c.filesDir, "radares.json")

    fun cargar(c: Context): BaseRadares {
        val incluida = BaseRadares.leer(c.assets.open("radares.json").bufferedReader().readText())
        val descargada = runCatching { BaseRadares.leer(archivo(c).readText()) }.getOrNull()
        return if (descargada != null && descargada.generado > incluida.generado) descargada else incluida
    }

    /** Descarga la base nueva (como mucho una vez al día). Devuelve la nueva o null. Llamar fuera del hilo principal. */
    fun actualizar(c: Context, actual: String): BaseRadares? {
        val ajustes = Ajustes(c)
        if (System.currentTimeMillis() - ajustes.ultimaConsultaBase < 86_400_000L) return null
        ajustes.ultimaConsultaBase = System.currentTimeMillis()
        return runCatching {
            val con = URL(DIRECCION).openConnection() as HttpURLConnection
            con.connectTimeout = 20_000; con.readTimeout = 40_000
            val texto = con.inputStream.bufferedReader().readText()
            val base = BaseRadares.leer(texto)
            if (base.radares.size < 2_000 || base.generado <= actual) null
            else { archivo(c).writeText(texto); base }
        }.getOrNull()
    }
}
