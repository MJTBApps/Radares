package es.mjtbapps.radares

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/**
 * Dice los avisos. Con una voz grabada encadena los audios de assets/<voz>/<pieza>.mp3;
 * si falta alguno, usa la voz del sistema (TextToSpeech) con el texto.
 */
class Voz(private val contexto: Context) {
    var salida = Salida.ALTAVOZ
    var voz = ""

    private val audio = contexto.getSystemService(AudioManager::class.java)
    private val hilo = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var ttsListo = false
    private val cola = ArrayDeque<Pair<String, List<String>?>>()
    private var hablando = false
    private var foco: AudioFocusRequest? = null
    private var reproductor: MediaPlayer? = null

    init {
        tts = TextToSpeech(contexto) { estado ->
            if (estado == TextToSpeech.SUCCESS) {
                tts?.language = Locale("es", "ES")
                ttsListo = true
            }
        }
    }

    fun apagar() {
        tts?.shutdown()
        reproductor?.release()
    }

    /** Voces grabadas que lleva la app (carpetas de assets con audios). */
    fun grabadas(): List<String> =
        (contexto.assets.list("") ?: emptyArray()).filter { (contexto.assets.list(it)?.size ?: 0) > 100 }.sorted()

    fun decir(texto: String, piezas: List<String>? = null) {
        cola.addLast(texto to piezas)
        if (hablando) return
        hablando = true
        val espera = abrir()
        hilo.postDelayed({ siguiente() }, espera)
    }

    private val atributos: AudioAttributes
        get() = AudioAttributes.Builder()
            .setUsage(if (salida == Salida.MULTIMEDIA) AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE
                      else AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

    /** Pide el foco de audio (la música baja) y prepara la ruta. Devuelve la espera en ms. */
    private fun abrir(): Long {
        val f = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(atributos).build()
        foco = f
        audio.requestAudioFocus(f)
        return when (salida) {
            Salida.MULTIMEDIA -> 100
            Salida.ALTAVOZ -> {
                audio.mode = AudioManager.MODE_IN_COMMUNICATION
                dispositivo(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
                150
            }
            Salida.LLAMADA -> {
                audio.mode = AudioManager.MODE_IN_COMMUNICATION
                if (!dispositivo(AudioDeviceInfo.TYPE_BLUETOOTH_SCO)) {
                    @Suppress("DEPRECATION") audio.startBluetoothSco()
                    @Suppress("DEPRECATION") audio.isBluetoothScoOn = true
                }
                // El canal de llamadas del coche tarda en abrirse.
                1_500
            }
        }
    }

    private fun dispositivo(tipo: Int): Boolean {
        if (Build.VERSION.SDK_INT >= 31) {
            val d = audio.availableCommunicationDevices.firstOrNull { it.type == tipo } ?: return false
            return audio.setCommunicationDevice(d)
        }
        if (tipo == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) { @Suppress("DEPRECATION") run { audio.isSpeakerphoneOn = true }; return true }
        return false
    }

    private fun siguiente() {
        val (texto, piezas) = cola.removeFirstOrNull() ?: return cerrar()
        val archivos = audios(piezas)
        if (archivos != null) reproducir(archivos) else hablarSistema(texto)
    }

    private fun audios(piezas: List<String>?): List<String>? {
        if (piezas.isNullOrEmpty() || !voz.startsWith("grabada:")) return null
        val carpeta = voz.removePrefix("grabada:")
        val hay = contexto.assets.list(carpeta)?.toSet() ?: return null
        val archivos = piezas.map { "$it.mp3" }
        return if (archivos.all { it in hay }) archivos.map { "$carpeta/$it" } else null
    }

    private fun reproducir(archivos: List<String>) {
        if (archivos.isEmpty()) { siguiente(); return }
        val r = MediaPlayer()
        reproductor = r
        try {
            contexto.assets.openFd(archivos.first()).use { fd -> r.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length) }
            r.setAudioAttributes(atributos)
            r.setOnCompletionListener { it.release(); reproducir(archivos.drop(1)) }
            r.setOnErrorListener { mp, _, _ -> mp.release(); reproducir(archivos.drop(1)); true }
            r.prepare()
            r.start()
        } catch (e: Exception) {
            r.release()
            Estado.anotar("Audio ${archivos.first()}: ${e.message}")
            reproducir(archivos.drop(1))
        }
    }

    private fun hablarSistema(texto: String) {
        val t = tts
        if (t == null || !ttsListo) { siguiente(); return }
        t.setAudioAttributes(atributos)
        t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String?) {}
            override fun onDone(id: String?) { hilo.post { siguiente() } }
            @Deprecated("Deprecated in Java")
            override fun onError(id: String?) { hilo.post { siguiente() } }
        })
        t.speak(texto, TextToSpeech.QUEUE_ADD, null, "aviso-${System.nanoTime()}")
    }

    private fun cerrar() {
        hablando = false
        if (salida != Salida.MULTIMEDIA) {
            if (Build.VERSION.SDK_INT >= 31) audio.clearCommunicationDevice()
            @Suppress("DEPRECATION") audio.stopBluetoothSco()
            @Suppress("DEPRECATION") run { audio.isSpeakerphoneOn = false }
            audio.mode = AudioManager.MODE_NORMAL
        }
        foco?.let { audio.abandonAudioFocusRequest(it) }
        foco = null
    }
}
