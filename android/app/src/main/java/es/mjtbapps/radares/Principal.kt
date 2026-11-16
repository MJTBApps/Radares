package es.mjtbapps.radares

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import es.mjtbapps.radares.nucleo.Frases

class Principal : ComponentActivity() {
    private lateinit var tienda: Tienda
    private lateinit var ajustes: Ajustes
    private var tras: (() -> Unit)? = null

    private val pedir = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { _ ->
        tras?.invoke(); tras = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ajustes = Ajustes(this)
        tienda = Tienda(this).also { it.conectar() }
        Vigilancia.crearCanal(this)
        Arranque.configurar(this)
        setContent {
            MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()) {
                Surface(Modifier.fillMaxWidth()) { Contenido() }
            }
        }
    }

    private fun empezar() {
        val faltan = mutableListOf<String>()
        if (!Vigilancia.tienePermiso(this)) faltan += Manifest.permission.ACCESS_FINE_LOCATION
        if (Build.VERSION.SDK_INT >= 33) faltan += Manifest.permission.POST_NOTIFICATIONS
        tras = { if (Vigilancia.tienePermiso(this)) Vigilancia.empezar(this) else Estado.anotar("Sin permiso de ubicación: actívalo en Ajustes.") }
        if (faltan.isEmpty()) tras!!.invoke().also { tras = null } else pedir.launch(faltan.toTypedArray())
    }

    /** Arranque automático: ubicación y actividad primero; la ubicación «todo el tiempo», después y aparte. */
    private fun activarArranque() {
        val faltan = Arranque.permisosQueFaltan(this)
        val primero = faltan.filter { it != Manifest.permission.ACCESS_BACKGROUND_LOCATION }
        tras = {
            if (Build.VERSION.SDK_INT >= 29 && Arranque.permisosQueFaltan(this) == listOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION)) {
                tras = { Arranque.configurar(this) }
                pedir.launch(arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION))
            } else Arranque.configurar(this)
        }
        if (primero.isNotEmpty()) pedir.launch(primero.toTypedArray()) else tras!!.invoke()
    }

    @Composable
    private fun Tarjeta(contenido: @Composable () -> Unit) {
        Column(
            Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(14.dp)).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) { contenido() }
    }

    @Composable
    private fun Contenido() {
        val e by Estado.pantalla.collectAsState()
        val ofertas by tienda.ofertas.collectAsState()
        val avisoTienda by tienda.aviso.collectAsState()
        var salida by remember { mutableStateOf(ajustes.salida) }
        var voz by remember { mutableStateOf(ajustes.voz) }
        var auto by remember { mutableStateOf(ajustes.arranqueAutomatico) }
        var dgt by remember { mutableStateOf(ajustes.avisosDGT) }
        val grabadas = remember { Voz(this).let { v -> v.grabadas().also { v.apagar() } } }
        if (voz.isEmpty() && grabadas.isNotEmpty()) { voz = "grabada:" + grabadas.first(); ajustes.voz = voz }

        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                val pasado = e.kmh != null && e.limite != null && (e.distancia ?: 9e9) < 1500 && e.kmh!! > e.limite!!
                Text(e.kmh?.toString() ?: "–", fontSize = 96.sp, fontWeight = FontWeight.Bold,
                    color = if (pasado) Color.Red else MaterialTheme.colorScheme.onSurface)
                Text("km/h", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Tarjeta {
                when {
                    e.titulo != null -> {
                        Text(e.titulo!!, fontWeight = FontWeight.SemiBold)
                        if (e.media != null) Text("Media ${e.media} km/h", fontSize = 30.sp, fontWeight = FontWeight.SemiBold)
                        else if (e.distancia != null) Text(Frases.distancia(e.distancia!!), fontSize = 30.sp, fontWeight = FontWeight.SemiBold)
                        Text(listOfNotNull(e.limite?.let { "Límite $it" }, e.via).joinToString(" · "),
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    !e.activo -> {
                        Text("Parado", fontWeight = FontWeight.SemiBold)
                        Text("Pulsa Empezar antes de salir. Puedes bloquear el móvil o usar otras apps.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    e.ahorro -> Text("Sin radares a menos de 10 km · GPS en ahorro", fontWeight = FontWeight.SemiBold)
                    else -> Text("Ningún radar delante · aviso unos 20 s antes", fontWeight = FontWeight.SemiBold)
                }
            }
            Button(
                onClick = { if (e.activo) Vigilancia.parar(this@Principal) else empezar() },
                modifier = Modifier.fillMaxWidth(),
                colors = if (e.activo) ButtonDefaults.buttonColors(containerColor = Color(0xFFD32F2F)) else ButtonDefaults.buttonColors(),
            ) { Text(if (e.activo) "Parar" else "Empezar", fontSize = 22.sp, modifier = Modifier.padding(6.dp)) }

            Tarjeta {
                Text("Dónde suena el aviso", fontWeight = FontWeight.SemiBold)
                Salida.entries.forEach { s ->
                    Row(Modifier.fillMaxWidth().selectable(s == salida) { salida = s; ajustes.salida = s },
                        verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = s == salida, onClick = null)
                        Spacer(Modifier.width(8.dp))
                        Text(s.titulo)
                    }
                }
                Text(salida.explicacion, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (salida == Salida.LLAMADA && !ajustes.llamadaDisponible) {
                    Text("La prueba ha terminado: ahora suena por el altavoz del móvil. Con Premium vuelve al coche.", color = Color(0xFFE65100))
                }
                HorizontalDivider()
                Text("Voz", fontWeight = FontWeight.SemiBold)
                (grabadas.map { "grabada:$it" } + "sistema").forEach { v ->
                    val nombre = if (v == "sistema") "La del móvil" else v.removePrefix("grabada:").replaceFirstChar { it.uppercase() } + " (natural)"
                    Row(Modifier.fillMaxWidth().selectable(v == voz) { voz = v; ajustes.voz = v }, verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = v == voz, onClick = null); Spacer(Modifier.width(8.dp)); Text(nombre)
                    }
                }
                if (voz.startsWith("grabada:")) Text("Las voces «natural» están generadas con inteligencia artificial y funcionan sin cobertura.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
                OutlinedButton(onClick = {
                    val v = Voz(this@Principal).also { it.salida = if (salida == Salida.LLAMADA && !ajustes.llamadaDisponible) Salida.ALTAVOZ else salida; it.voz = voz }
                    // El motor de voz del sistema tarda un momento en estar listo.
                    window.decorView.postDelayed({ v.decir("Prueba. Radar a 500 metros. Límite 120.", listOf("prueba", "radar_500", "limite_120")) }, 800)
                }) { Text("Probar ahora") }
            }

            Tarjeta {
                if (ajustes.premium) {
                    Text("Premium activo", fontWeight = FontWeight.SemiBold)
                    Text("El aviso por los altavoces del coche está desbloqueado. Gracias por apoyar la app.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    Text("Premium", fontWeight = FontWeight.SemiBold)
                    val dias = ajustes.diasDePruebaRestantes
                    Text(if (dias > 0) "El aviso por los altavoces del coche es de Premium. Lo estás probando gratis: quedan $dias días."
                         else "El aviso por los altavoces del coche es de Premium. Los avisos por el móvil siguen siendo gratis.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    ofertas.forEach { o ->
                        Button(onClick = { tienda.comprar(this@Principal, o) }, modifier = Modifier.fillMaxWidth()) { Text("${o.titulo} · ${o.precio}") }
                    }
                    TextButton(onClick = { tienda.comprobarCompras() }) { Text("Restaurar compras") }
                    avisoTienda?.let { Text(it, color = Color(0xFFE65100)) }
                    Text("La suscripción anual se renueva sola hasta que la canceles en Google Play → Pagos y suscripciones.",
                        fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            Tarjeta {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Empezar sola al ir en coche", Modifier.weight(1f))
                    Switch(checked = auto, onCheckedChange = { auto = it; ajustes.arranqueAutomatico = it; if (it) activarArranque() else Arranque.configurar(this@Principal) })
                }
                Text("Detecta que vas en coche y se pone a vigilar sin abrir la app. Al aparcar se apaga sola. Necesita la ubicación «Permitir todo el tiempo».",
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (auto && Arranque.permisosQueFaltan(this@Principal).isNotEmpty()) {
                    TextButton(onClick = {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    }) { Text("Faltan permisos: abrir ajustes") }
                }
                HorizontalDivider()
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Avisos de tráfico de la DGT", Modifier.weight(1f))
                    Switch(checked = dgt, onCheckedChange = { dgt = it; ajustes.avisosDGT = it })
                }
                Text("Accidentes, retenciones, obstáculos y mal tiempo en tu carretera, a unos 2 km. Usa unos 2 MB de datos por hora de viaje.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("El próximo radar aparece en la notificación, también con la pantalla bloqueada.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
            }

            if (e.diario.isNotEmpty()) Tarjeta {
                Text("Últimos avisos", fontWeight = FontWeight.SemiBold)
                e.diario.take(8).forEach { Text(it, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }

            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                val pie = listOfNotNull(
                    "No avisa de radares móviles. Respeta siempre los límites.",
                    e.incidencias?.let { "$it incidencias de la DGT en este momento" },
                    "Datos: © colaboradores de OpenStreetMap (ODbL), Servei Català de Trànsit y DGT.",
                )
                pie.forEach { Text(it, fontSize = 12.sp, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                TextButton(onClick = {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://mjtbapps.github.io/chivato-radar/privacidad.html")))
                }) { Text("Política de privacidad") }
            }
        }
    }
}
