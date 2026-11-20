package es.mjtbapps.radares

import android.app.Activity
import android.os.Bundle
import android.os.SystemClock
import com.google.ads.mediation.admob.AdMobAdapter
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.appopen.AppOpenAd
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import androidx.compose.foundation.layout.fillMaxWidth

/**
 * Un anuncio de Google (AdMob) al abrir la app, solo sin Premium. Igual que en el iPhone:
 * nunca yendo rápido, como mucho uno cada 4 horas y, antes, el formulario de consentimiento (RGPD).
 * El ID de la app de AdMob va en AndroidManifest.xml.
 */
object Anuncios {
    private const val BLOQUE_AL_ABRIR = "ca-app-pub-1535697166232113/5115133756"

    private var iniciado = false
    private var mostrando = false
    private var ultimo = 0L

    /** `puede` se vuelve a consultar justo antes de mostrarlo. */
    fun alAbrir(actividad: Activity, puede: () -> Boolean) {
        if (!puede() || mostrando) return
        if (ultimo != 0L && SystemClock.elapsedRealtime() - ultimo < 4 * 3600_000L) return

        val consentimiento = UserMessagingPlatform.getConsentInformation(actividad)
        consentimiento.requestConsentInfoUpdate(actividad, ConsentRequestParameters.Builder().build(), {
            UserMessagingPlatform.loadAndShowConsentFormIfRequired(actividad) { _ ->
                if (consentimiento.canRequestAds()) cargarYMostrar(actividad, puede)
            }
        }, { _ -> })
    }

    private fun cargarYMostrar(actividad: Activity, puede: () -> Boolean) {
        if (!iniciado) {
            MobileAds.initialize(actividad.applicationContext)
            iniciado = true
        }
        val pedido = SystemClock.elapsedRealtime()
        // Anuncios no personalizados: la app no hace seguimiento.
        val extras = Bundle().apply { putString("npa", "1") }
        val peticion = AdRequest.Builder().addNetworkExtrasBundle(AdMobAdapter::class.java, extras).build()
        AppOpenAd.load(actividad, BLOQUE_AL_ABRIR, peticion, object : AppOpenAd.AppOpenAdLoadCallback() {
            override fun onAdLoaded(anuncio: AppOpenAd) {
                // Si tarda más de 5 s ya no se muestra: el usuario estará usando la app.
                if (SystemClock.elapsedRealtime() - pedido > 5000 || !puede() || actividad.isFinishing) return
                anuncio.fullScreenContentCallback = object : FullScreenContentCallback() {
                    override fun onAdDismissedFullScreenContent() { mostrando = false }
                    override fun onAdFailedToShowFullScreenContent(error: AdError) { mostrando = false }
                }
                mostrando = true
                ultimo = SystemClock.elapsedRealtime()
                anuncio.show(actividad)
            }
            override fun onAdFailedToLoad(error: LoadAdError) {}
        })
    }
}

/** Banner de AdMob al pie de la pantalla (solo sin Premium y con el consentimiento resuelto). */
@androidx.compose.runtime.Composable
fun BannerAnuncio() {
    val anchoDp = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp
    androidx.compose.ui.viewinterop.AndroidView(
        modifier = androidx.compose.ui.Modifier.fillMaxWidth(),
        factory = { ctx ->
            MobileAds.initialize(ctx.applicationContext)
            com.google.android.gms.ads.AdView(ctx).apply {
                setAdSize(com.google.android.gms.ads.AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(ctx, anchoDp))
                adUnitId = "ca-app-pub-1535697166232113/2739719020"
                val extras = Bundle().apply { putString("npa", "1") }
                loadAd(AdRequest.Builder().addNetworkExtrasBundle(AdMobAdapter::class.java, extras).build())
            }
        },
    )
}
