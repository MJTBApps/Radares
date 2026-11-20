package es.mjtbapps.radares

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity

/**
 * Arranque automático: Android avisa cuando detecta que empezamos a ir en coche
 * (reconocimiento de actividad) y entonces se pone en marcha la vigilancia.
 * Al aparcar, la vigilancia se apaga sola a los 5 minutos sin moverse.
 */
object Arranque {
    private fun intento(c: Context) = PendingIntent.getBroadcast(
        c, 7, Intent(c, AlEntrarEnCoche::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
    )

    fun permisosQueFaltan(c: Context): List<String> {
        val lista = mutableListOf<String>()
        fun falta(p: String) = ContextCompat.checkSelfPermission(c, p) != PackageManager.PERMISSION_GRANTED
        if (falta(Manifest.permission.ACCESS_FINE_LOCATION)) lista += Manifest.permission.ACCESS_FINE_LOCATION
        if (Build.VERSION.SDK_INT >= 29 && falta(Manifest.permission.ACTIVITY_RECOGNITION)) lista += Manifest.permission.ACTIVITY_RECOGNITION
        if (Build.VERSION.SDK_INT >= 29 && falta(Manifest.permission.ACCESS_BACKGROUND_LOCATION)) lista += Manifest.permission.ACCESS_BACKGROUND_LOCATION
        return lista
    }

    @SuppressLint("MissingPermission")
    fun configurar(c: Context) {
        val cliente = ActivityRecognition.getClient(c)
        // Es de Premium (o durante los días de prueba).
        val a = Ajustes(c)
        if (!a.arranqueAutomatico || !a.llamadaDisponible || permisosQueFaltan(c).isNotEmpty()) {
            runCatching { cliente.removeActivityTransitionUpdates(intento(c)) }
            return
        }
        val transiciones = listOf(
            ActivityTransition.Builder().setActivityType(DetectedActivity.IN_VEHICLE)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER).build(),
        )
        cliente.requestActivityTransitionUpdates(ActivityTransitionRequest(transiciones), intento(c))
            .addOnFailureListener { Estado.anotar("No se ha podido activar el arranque automático: ${it.message}") }
    }
}

/** Recibe «has empezado a ir en coche». */
class AlEntrarEnCoche : BroadcastReceiver() {
    override fun onReceive(c: Context, intent: Intent) {
        if (!ActivityTransitionResult.hasResult(intent)) return
        val resultado = ActivityTransitionResult.extractResult(intent) ?: return
        val enCoche = resultado.transitionEvents.any {
            it.activityType == DetectedActivity.IN_VEHICLE && it.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER
        }
        if (enCoche && Ajustes(c).arranqueAutomatico && Ajustes(c).llamadaDisponible && !Estado.pantalla.value.activo && Vigilancia.tienePermiso(c)) {
            Vigilancia.empezar(c, sola = true)
        }
    }
}

/** Tras reiniciar el móvil o actualizar la app hay que volver a pedir los avisos de actividad. */
class AlArrancar : BroadcastReceiver() {
    override fun onReceive(c: Context, intent: Intent) {
        Arranque.configurar(c)
    }
}
