package es.mjtbapps.radares

import es.mjtbapps.radares.nucleo.BaseRadares
import es.mjtbapps.radares.nucleo.Evento
import es.mjtbapps.radares.nucleo.Frases
import es.mjtbapps.radares.nucleo.Geo
import es.mjtbapps.radares.nucleo.Incidencia
import es.mjtbapps.radares.nucleo.LectorIncidenciasDGT
import es.mjtbapps.radares.nucleo.MotorAvisos
import es.mjtbapps.radares.nucleo.MotorIncidencias
import es.mjtbapps.radares.nucleo.Posicion
import es.mjtbapps.radares.nucleo.Radar
import es.mjtbapps.radares.nucleo.TipoIncidencia
import es.mjtbapps.radares.nucleo.TipoRadar
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.OffsetDateTime

/** Las mismas comprobaciones que RadaresChecks (Swift), para que las dos apps se comporten igual. */
class NucleoTest {
    private val inicio = 41.60 to 1.80

    private fun conducir(m: MotorAvisos, rumbo: Double, kmh: Double, metros: Double): List<Pair<Evento, Double>> {
        val v = kmh / 3.6
        val salida = ArrayList<Pair<Evento, Double>>()
        var s = 0.0; var t = 0.0
        while (s <= metros) {
            val (la, lo) = Geo.avanzar(inicio.first, inicio.second, rumbo, s)
            m.procesar(Posicion(la, lo, v, rumbo, 5.0, t)).forEach { salida += it to s }
            s += v; t += 1
        }
        return salida
    }

    @Test fun radarDelanteAvisaUnaVezCon20s() {
        val (la, lo) = Geo.avanzar(inicio.first, inicio.second, 90.0, 3000.0)
        val e = conducir(MotorAvisos(listOf(Radar("a", la, lo, limite = 120))), 90.0, 120.0, 6000.0)
        assertEquals(1, e.size)
        val d = (e[0].first as Evento.Radar).distancia
        assertTrue("$d", d > 620 && d <= 667)
    }

    @Test fun sentidoContrarioNoAvisa() {
        val (la, lo) = Geo.avanzar(inicio.first, inicio.second, 90.0, 3000.0)
        assertTrue(conducir(MotorAvisos(listOf(Radar("c", la, lo, rumbo = 270.0))), 90.0, 100.0, 5000.0).isEmpty())
    }

    @Test fun tramoMediaYFin() {
        val (la, lo) = Geo.avanzar(inicio.first, inicio.second, 90.0, 2000.0)
        val tramo = Radar("t", la, lo, TipoRadar.TRAMO, limite = 100, longitud = 3000.0)
        val e = conducir(MotorAvisos(listOf(tramo)), 90.0, 110.0, 7000.0)
        assertEquals(3, e.size)
        assertEquals(110, (e[1].first as Evento.ExcesoTramo).media)
    }

    @Test fun frasesYPiezasCoincidenConElCatalogo() {
        assertEquals("650 metros", Frases.distancia(640.0))
        assertEquals("7,5 kilómetros", Frases.distancia(7300.0))
        val evento = Evento.Radar(Radar("a", 0.0, 0.0, limite = 120), 640.0, 131)
        assertEquals("Radar a 650 metros. Límite 120. Vas a 131.", Frases.texto(evento))
        assertEquals(listOf("radar_650", "limite_120", "vas_131"), Frases.piezas(evento))
        // Todas las piezas posibles están en el catálogo que genera la app de iPhone.
        val catalogo = File("../../scripts/catalogo_voces.json")
        if (catalogo.exists()) {
            val claves = JSONArray(catalogo.readText()).let { a -> (0 until a.length()).map { a.getJSONObject(it).getString("clave") }.toSet() }
            var d = 150.0
            while (d < 2100) {
                TipoIncidencia.entries.forEach { t -> Frases.piezas(Evento.Incidencia(Incidencia("i", t, 0.0, 0.0), d))!!.forEach { assertTrue(it, it in claves) } }
                Frases.piezas(Evento.Radar(Radar("a", 0.0, 0.0, TipoRadar.TRAMO, limite = 100, longitud = 7300.0), d, 131))!!.forEach { assertTrue(it, it in claves) }
                d += 37
            }
        }
    }

    @Test fun incidenciasDGT() {
        val xml = """
            <d2:payload xmlns:d2="a" xmlns:sit="b" xmlns:loc="c" xmlns:com="d">
            <sit:situation id="1"><sit:situationRecord id="r1">
              <com:overallStartTime>2026-11-16T10:00:00.000+01:00</com:overallStartTime>
              <sit:cause><sit:causeType>accident</sit:causeType></sit:cause>
              <loc:roadName>A-7</loc:roadName>
              <loc:tpegLinearLocation><loc:tpegDirection>northBound</loc:tpegDirection>
                <loc:to><loc:pointCoordinates><loc:latitude>41.62</loc:latitude><loc:longitude>1.80</loc:longitude></loc:pointCoordinates></loc:to>
                <loc:from><loc:pointCoordinates><loc:latitude>41.61</loc:latitude><loc:longitude>1.80</loc:longitude></loc:pointCoordinates></loc:from>
              </loc:tpegLinearLocation>
            </sit:situationRecord></sit:situation>
            <sit:situation id="2"><sit:situationRecord id="r2">
              <com:overallStartTime>2026-05-01T10:00:00.000+01:00</com:overallStartTime>
              <sit:cause><sit:causeType>accident</sit:causeType></sit:cause>
              <loc:to><loc:pointCoordinates><loc:latitude>40</loc:latitude><loc:longitude>-3</loc:longitude></loc:pointCoordinates></loc:to>
            </sit:situationRecord></sit:situation>
            </d2:payload>
        """.trimIndent()
        val ahora = OffsetDateTime.parse("2026-11-16T12:00:00Z").toEpochSecond().toDouble()
        val lista = LectorIncidenciasDGT.leer(xml.byteInputStream(), ahora)
        assertEquals(1, lista.size)
        assertEquals("A-7", lista[0].via)
        assertEquals(41.61, lista[0].lat, 1e-9)

        val (la, lo) = Geo.avanzar(inicio.first, inicio.second, 0.0, 5000.0)
        val m = MotorIncidencias()
        m.cambiar(listOf(Incidencia("x", TipoIncidencia.RETENCION, la, lo, 0.0), Incidencia("y", TipoIncidencia.ACCIDENTE, la, lo, 180.0)))
        val avisos = ArrayList<Evento>()
        var s = 0.0
        while (s < 6000) {
            val (a, b) = Geo.avanzar(inicio.first, inicio.second, 0.0, s)
            avisos += m.procesar(Posicion(a, b, 25.0, 0.0, 5.0, s)); s += 25
        }
        assertEquals(1, avisos.size)
        assertEquals("Retención a 2 kilómetros.", Frases.texto(avisos[0]))
    }

    @Test fun baseRealSeLee() {
        val f = File("../../ios/Radares/Recursos/radares.json")
        if (!f.exists()) return
        val base = BaseRadares.leer(f.readText())
        assertTrue(base.radares.size > 3000)
        assertEquals(base.radares.size, base.radares.map { it.id }.toSet().size)
    }
}
