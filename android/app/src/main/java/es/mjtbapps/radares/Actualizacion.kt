package es.mjtbapps.radares

import android.content.Context
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.model.UpdateAvailability
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Pregunta a Google Play si hay una versión más nueva instalable. Solo funciona con la app
 * instalada desde Play; en una APK de prueba no avisa nunca.
 */
object Actualizacion {
    private val _hay = MutableStateFlow(false)
    val hay: StateFlow<Boolean> = _hay

    fun comprobar(contexto: Context) {
        runCatching {
            AppUpdateManagerFactory.create(contexto).appUpdateInfo
                .addOnSuccessListener { _hay.value = it.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE }
        }
    }
}
