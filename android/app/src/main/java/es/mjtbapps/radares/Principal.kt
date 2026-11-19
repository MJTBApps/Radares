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
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
            val azul = Color(0xFF1B4DB1)
            MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme(primary = Color(0xFF8FB4FF), onPrimary = Color(0xFF0F1830))
                else lightColorScheme(primary = azul, onPrimary = Color.White)) {
                Surface(Modifier.fillMaxSize()) { Contenido() }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        Actualizacion.comprobar(this)
        // Espera a que la tienda confirme si hay Premium antes de decidir el anuncio.
        window.decorView.postDelayed({
            Anuncios.alAbrir(this) { !ajustes.premium && (Estado.pantalla.value.kmh ?: 0) < 10 }
        }, 1500)
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
    private fun Tarjeta(contenido: @Composable ColumnScope.() -> Unit) {
        Column(
            Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(20.dp)).padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = contenido,
        )
    }

    @Composable
    private fun Gris(texto: String, tam: Int = 14) =
        Text(texto, fontSize = tam.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, lineHeight = (tam + 5).sp)

    /** Señal de límite: círculo blanco con borde rojo. */
    @Composable
    private fun Limite(valor: Int, tam: Int = 56) {
        Box(Modifier.size(tam.dp).background(Color.White, CircleShape).border((tam / 9).dp, Color(0xFFD32F2F), CircleShape),
            contentAlignment = Alignment.Center) {
            Text("$valor", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = (tam * 0.38).sp)
        }
    }

    @Composable
    private fun Interruptor(titulo: String, explicacion: String, valor: Boolean, cambio: (Boolean) -> Unit) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(titulo, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Gris(explicacion, 13)
            }
            Spacer(Modifier.width(12.dp))
            Switch(checked = valor, onCheckedChange = cambio)
        }
    }

    @Composable
    private fun Contenido() {
        val e by Estado.pantalla.collectAsState()
        val ofertas by tienda.ofertas.collectAsState()
        val avisoTienda by tienda.aviso.collectAsState()
        val nueva by Actualizacion.hay.collectAsState()
        var salida by remember { mutableStateOf(ajustes.salida) }
        var auto by remember { mutableStateOf(ajustes.arranqueAutomatico) }
        var dgt by remember { mutableStateOf(ajustes.avisosDGT) }
        var menu by remember { mutableStateOf(false) }
        val rojo = Color(0xFFD32F2F)

        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Text("Chivato Radar", fontSize = 22.sp, fontWeight = FontWeight.Bold)

            if (nueva) {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(MaterialTheme.colorScheme.primary)
                        .clickable {
                            runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName"))) }
                                .onFailure { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$packageName"))) }
                        }.padding(18.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("Hay una versión nueva", fontWeight = FontWeight.SemiBold, fontSize = 16.sp, color = MaterialTheme.colorScheme.onPrimary)
                        Text("Toca para actualizar en Google Play", fontSize = 13.sp, color = MaterialTheme.colorScheme.onPrimary)
                    }
                    Text("›", fontSize = 28.sp, color = MaterialTheme.colorScheme.onPrimary)
                }
            }

            // Velocidad en un anillo: rojo si vas por encima del límite del radar cercano.
            val pasado = e.kmh != null && e.limite != null && (e.distancia ?: 9e9) < 1500 && e.kmh!! > e.limite!!
            val anillo = when { pasado -> rojo; e.activo -> MaterialTheme.colorScheme.primary; else -> MaterialTheme.colorScheme.outlineVariant }
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Box(Modifier.size(200.dp).border(10.dp, anillo, CircleShape), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(e.kmh?.toString() ?: "–", fontSize = 72.sp, fontWeight = FontWeight.Bold,
                            color = if (pasado) rojo else MaterialTheme.colorScheme.onSurface)
                        Gris("km/h")
                    }
                }
            }

            Tarjeta {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        when {
                            e.titulo != null -> {
                                Text(e.titulo!!, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                                val grande = if (e.media != null) "Media ${e.media} km/h" else e.distancia?.let { Frases.distancia(it) }
                                grande?.let { Text(it, fontSize = 28.sp, fontWeight = FontWeight.Bold) }
                                e.via?.let { Gris(it) }
                            }
                            !e.activo -> {
                                Text("Parado", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                                Gris("Pulsa Empezar antes de salir. Puedes bloquear el móvil o usar otras apps.")
                            }
                            e.ahorro -> Text("Sin radares cerca · GPS en ahorro", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                            else -> {
                                Text("Ningún radar delante", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                                Gris("Te aviso unos 20 segundos antes.")
                            }
                        }
                    }
                    if (e.titulo != null) e.limite?.let { Spacer(Modifier.width(12.dp)); Limite(it) }
                }
            }

            Button(
                onClick = { if (e.activo) Vigilancia.parar(this@Principal) else empezar() },
                modifier = Modifier.fillMaxWidth().height(60.dp),
                shape = RoundedCornerShape(30.dp),
                colors = if (e.activo) ButtonDefaults.buttonColors(containerColor = rojo) else ButtonDefaults.buttonColors(),
            ) { Text(if (e.activo) "Parar" else "Empezar", fontSize = 20.sp, fontWeight = FontWeight.SemiBold) }

            Text("Ajustes", fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 6.dp))
            Tarjeta {
                Text("Dónde suena el aviso", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Box {
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                            .background(MaterialTheme.colorScheme.surface).clickable { menu = true }
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(salida.titulo, Modifier.weight(1f), fontSize = 16.sp)
                        Text("▾", fontSize = 18.sp, color = MaterialTheme.colorScheme.primary)
                    }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        Salida.entries.forEach { s ->
                            DropdownMenuItem(text = { Text(s.titulo) }, onClick = { salida = s; ajustes.salida = s; menu = false })
                        }
                    }
                }
                Gris(salida.explicacion, 13)
                if (salida == Salida.LLAMADA && !ajustes.llamadaDisponible) {
                    Text("La prueba ha terminado: ahora suena por el altavoz del móvil. Con Premium vuelve al coche.",
                        color = Color(0xFFE65100), fontSize = 13.sp)
                }
                OutlinedButton(onClick = {
                    val v = Voz(this@Principal).also { it.salida = if (salida == Salida.LLAMADA && !ajustes.llamadaDisponible) Salida.ALTAVOZ else salida; it.voz = "sistema" }
                    // El motor de voz del sistema tarda un momento en estar listo.
                    window.decorView.postDelayed({ v.decir("Prueba. Radar a 500 metros. Límite 120.") }, 800)
                }, shape = RoundedCornerShape(20.dp)) { Text("Probar el aviso") }
            }

            Tarjeta {
                Interruptor("Empezar sola al ir en coche",
                    "Se pone a vigilar sola al ir en coche y se apaga al aparcar. Necesita la ubicación «Permitir todo el tiempo».", auto) {
                    auto = it; ajustes.arranqueAutomatico = it; if (it) activarArranque() else Arranque.configurar(this@Principal)
                }
                if (auto && Arranque.permisosQueFaltan(this@Principal).isNotEmpty()) {
                    TextButton(onClick = {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    }) { Text("Faltan permisos: abrir ajustes") }
                }
                HorizontalDivider()
                Interruptor("Avisos de tráfico de la DGT",
                    "Accidentes, retenciones y obstáculos en tu carretera, a unos 2 km.", dgt) { dgt = it; ajustes.avisosDGT = it }
            }

            Tarjeta {
                if (ajustes.premium) {
                    Text("★ Premium activo", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                    Gris("El aviso por los altavoces del coche está desbloqueado. Gracias por apoyar la app.")
                } else {
                    Text("★ Premium", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                    val dias = ajustes.diasDePruebaRestantes
                    Gris(if (dias > 0) "El aviso por los altavoces del coche es de Premium. Lo estás probando gratis: quedan $dias días."
                         else "El aviso por los altavoces del coche es de Premium. Los avisos por el móvil siguen siendo gratis.")
                    ofertas.forEach { o ->
                        Button(onClick = { tienda.comprar(this@Principal, o) }, modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(20.dp)) { Text("${o.titulo} · ${o.precio}") }
                    }
                    TextButton(onClick = { tienda.comprobarCompras() }) { Text("Restaurar compras") }
                    avisoTienda?.let { Text(it, color = Color(0xFFE65100), fontSize = 13.sp) }
                    Gris("La suscripción anual se renueva sola hasta que la canceles en Google Play → Pagos y suscripciones.", 12)
                }
            }

            if (e.diario.isNotEmpty()) Tarjeta {
                Text("Últimos avisos", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                e.diario.take(6).forEach { Gris(it, 12) }
            }

            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                listOfNotNull(
                    "No avisa de radares móviles. Respeta siempre los límites.",
                    e.incidencias?.let { "$it incidencias de la DGT en este momento" },
                    "Datos: © colaboradores de OpenStreetMap (ODbL), Servei Català de Trànsit y DGT.",
                ).forEach { Text(it, fontSize = 12.sp, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                TextButton(onClick = {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://mjtbapps.github.io/chivato-radar/privacidad.html")))
                }) { Text("Política de privacidad") }
            }
        }
    }
}
