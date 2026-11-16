package es.mjtbapps.radares

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * Premium con Google Play: suscripción anual o pago único. Cualquiera de los dos desbloquea
 * el aviso por los altavoces del coche. Los productos se crean en Play Console con estos ids.
 */
class Tienda(private val contexto: Context) {
    companion object {
        const val ANUAL = "premium_anual"
        const val SIEMPRE = "premium_siempre"
    }

    data class Oferta(val id: String, val titulo: String, val precio: String, val detalles: ProductDetails)

    val ofertas = MutableStateFlow<List<Oferta>>(emptyList())
    val aviso = MutableStateFlow<String?>(null)
    private val ajustes = Ajustes(contexto)

    private val cliente: BillingClient = BillingClient.newBuilder(contexto)
        .setListener { r, compras -> if (r.responseCode == BillingClient.BillingResponseCode.OK) compras?.forEach(::procesar) }
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .build()

    fun conectar() {
        cliente.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(r: BillingResult) {
                if (r.responseCode != BillingClient.BillingResponseCode.OK) {
                    aviso.value = "Google Play no está disponible ahora."
                    return
                }
                comprobarCompras()
                cargar()
            }
            override fun onBillingServiceDisconnected() {}
        })
    }

    private fun cargar() {
        val lista = mutableListOf<Oferta>()
        fun pedir(tipo: String, id: String, fin: () -> Unit) {
            val p = QueryProductDetailsParams.newBuilder().setProductList(listOf(
                QueryProductDetailsParams.Product.newBuilder().setProductId(id).setProductType(tipo).build())).build()
            cliente.queryProductDetailsAsync(p) { _, resultado ->
                resultado.productDetailsList.forEach { d ->
                    val precio = if (tipo == BillingClient.ProductType.SUBS)
                        d.subscriptionOfferDetails?.firstOrNull()?.pricingPhases?.pricingPhaseList?.lastOrNull()?.formattedPrice?.let { "$it al año" }
                    else d.oneTimePurchaseOfferDetails?.formattedPrice?.let { "$it, un solo pago" }
                    if (precio != null) lista += Oferta(id, d.name, precio, d)
                }
                fin()
            }
        }
        pedir(BillingClient.ProductType.SUBS, ANUAL) {
            pedir(BillingClient.ProductType.INAPP, SIEMPRE) { ofertas.value = lista.toList() }
        }
    }

    fun comprar(actividad: Activity, oferta: Oferta) {
        val producto = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(oferta.detalles)
        oferta.detalles.subscriptionOfferDetails?.firstOrNull()?.offerToken?.let { producto.setOfferToken(it) }
        val r = cliente.launchBillingFlow(actividad, BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(producto.build())).build())
        if (r.responseCode != BillingClient.BillingResponseCode.OK) aviso.value = "No se ha podido abrir la compra."
    }

    /** También sirve para «Restaurar compras». */
    fun comprobarCompras() {
        var tiene = false
        cliente.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build()) { _, subs ->
            subs.forEach(::procesar)
            tiene = subs.any { it.purchaseState == Purchase.PurchaseState.PURCHASED }
            cliente.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()) { _, unicas ->
                unicas.forEach(::procesar)
                ajustes.premium = tiene || unicas.any { it.purchaseState == Purchase.PurchaseState.PURCHASED }
            }
        }
    }

    private fun procesar(c: Purchase) {
        if (c.purchaseState != Purchase.PurchaseState.PURCHASED) return
        ajustes.premium = true
        if (!c.isAcknowledged) {
            cliente.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(c.purchaseToken).build()) {}
        }
    }
}
