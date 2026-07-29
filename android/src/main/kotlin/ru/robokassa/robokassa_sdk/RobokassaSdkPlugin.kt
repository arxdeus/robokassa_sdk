package ru.robokassa.robokassa_sdk

import android.app.Activity
import android.content.Intent
import com.robokassa.library.models.Culture
import com.robokassa.library.models.Currency
import com.robokassa.library.models.PayActionState
import com.robokassa.library.models.PayRecurrentState
import com.robokassa.library.models.PaymentMethod
import com.robokassa.library.models.PaymentObject
import com.robokassa.library.models.Receipt
import com.robokassa.library.models.ReceiptItem
import com.robokassa.library.models.Tax
import com.robokassa.library.models.TaxSystem
import com.robokassa.library.params.CustomerParams
import com.robokassa.library.params.OrderParams
import com.robokassa.library.params.PaymentParams
import com.robokassa.library.params.ViewParams
import com.robokassa.library.pay.PaymentAction
import com.robokassa.library.pay.RobokassaPayLauncher
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.util.Date

/**
 * Bridges Flutter to Robokassa's official Android SDK.
 *
 * The checkout screen is `RobokassaActivity`, which the SDK exposes through
 * [RobokassaPayLauncher.Contract] — an `ActivityResultContract`. A Flutter
 * plugin has no `ComponentActivity` of its own to call
 * `registerForActivityResult` on, so this drives the contract manually:
 * `createIntent` to build the intent, `parseResult` to decode the outcome.
 * Reusing the SDK's own decoding beats re-reading its intent extras by hand.
 */
class RobokassaSdkPlugin :
    FlutterPlugin,
    ActivityAware,
    RobokassaHostApi,
    PluginRegistry.ActivityResultListener {

    private companion object {
        /** Arbitrary but stable; must not collide with the host app's codes. */
        const val REQUEST_CODE_PAYMENT = 41291

        const val ERROR_NO_ACTIVITY = "no_activity"
        const val ERROR_BUSY = "busy"
        const val ERROR_NATIVE = "robokassa_native_error"
    }

    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPayment: ((Result<RkPaymentResultMessage>) -> Unit)? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        RobokassaHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        RobokassaHostApi.setUp(binding.binaryMessenger, null)
        scope.cancel()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // A configuration change detaches and immediately re-attaches, so the
        // in-flight checkout must survive: drop the listener but keep the
        // pending callback for `onReattachedToActivityForConfigChanges`.
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        // The result can no longer be delivered; fail the call rather than
        // leaving the Dart future pending forever.
        val callback = pendingPayment ?: return
        pendingPayment = null
        callback(
            Result.failure(
                FlutterError(
                    ERROR_NO_ACTIVITY,
                    "The host Activity went away while the Robokassa checkout was open."
                )
            )
        )
    }

    // -------------------------------------------------------------------------
    // RobokassaHostApi
    // -------------------------------------------------------------------------

    override fun isNativeSdkAvailable(): Boolean = try {
        Class.forName("com.robokassa.library.pay.RobokassaPayLauncher")
        true
    } catch (_: Throwable) {
        false
    }

    override fun startPayment(
        request: RkPaymentRequest,
        callback: (Result<RkPaymentResultMessage>) -> Unit
    ) {
        launchCheckout(request, onlyCheck = false, callback = callback)
    }

    override fun checkPaymentState(
        request: RkPaymentRequest,
        callback: (Result<RkPaymentResultMessage>) -> Unit
    ) {
        // `onlyCheck` opens RobokassaActivity with its WebView hidden: it just
        // polls the state service and returns through the same contract.
        launchCheckout(request, onlyCheck = true, callback = callback)
    }

    override fun confirmHold(request: RkPaymentRequest, callback: (Result<Boolean>) -> Unit) {
        runPaymentAction(request, callback) { action, params -> action.confirmHold(params) }
    }

    override fun cancelHold(request: RkPaymentRequest, callback: (Result<Boolean>) -> Unit) {
        runPaymentAction(request, callback) { action, params -> action.cancelHold(params) }
    }

    override fun chargeRecurring(request: RkPaymentRequest, callback: (Result<Boolean>) -> Unit) {
        runPaymentAction(request, callback) { action, params -> action.payRecurrent(params) }
    }

    // -------------------------------------------------------------------------
    // Checkout
    // -------------------------------------------------------------------------

    private fun launchCheckout(
        request: RkPaymentRequest,
        onlyCheck: Boolean,
        callback: (Result<RkPaymentResultMessage>) -> Unit
    ) {
        val activity: Activity? = activityBinding?.activity
        if (activity == null) {
            callback(
                Result.failure(
                    FlutterError(
                        ERROR_NO_ACTIVITY,
                        "Robokassa checkout needs a foreground Activity, but the plugin is " +
                            "not attached to one."
                    )
                )
            )
            return
        }
        if (pendingPayment != null) {
            callback(
                Result.failure(
                    FlutterError(
                        ERROR_BUSY,
                        "A Robokassa checkout is already in progress. Await the first call " +
                            "before starting another."
                    )
                )
            )
            return
        }

        val params = try {
            request.toPaymentParams()
        } catch (error: Throwable) {
            callback(Result.failure(FlutterError(ERROR_NATIVE, error.message ?: "$error")))
            return
        }

        pendingPayment = callback
        try {
            val intent = RobokassaPayLauncher.Contract.createIntent(
                activity,
                RobokassaPayLauncher.StartPay(
                    paymentParams = params,
                    testMode = request.credentials.isTest,
                    onlyCheck = onlyCheck
                )
            )
            activity.startActivityForResult(intent, REQUEST_CODE_PAYMENT)
        } catch (error: Throwable) {
            pendingPayment = null
            callback(
                Result.failure(
                    FlutterError(
                        ERROR_NATIVE,
                        "Could not open the Robokassa checkout screen: ${error.message ?: error}"
                    )
                )
            )
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_PAYMENT) return false
        val callback = pendingPayment ?: return true
        pendingPayment = null

        val message = when (
            val parsed = RobokassaPayLauncher.Contract.parseResult(resultCode, data)
        ) {
            is RobokassaPayLauncher.Success -> RkPaymentResultMessage(
                outcome = RkPaymentOutcome.SUCCESS,
                invoiceId = parsed.invoiceId?.toLong(),
                opKey = parsed.opKey,
                resultCode = parsed.resultCode?.code,
                stateCode = parsed.stateCode?.code
            )

            is RobokassaPayLauncher.Error -> RkPaymentResultMessage(
                outcome = RkPaymentOutcome.ERROR,
                resultCode = parsed.resultCode?.code,
                stateCode = parsed.stateCode?.code,
                stateDescription = parsed.desc,
                errorMessage = parsed.error?.message
                    ?: parsed.desc
                    ?: "The Robokassa checkout reported an error."
            )

            RobokassaPayLauncher.Canceled -> RkPaymentResultMessage(
                outcome = RkPaymentOutcome.CANCELED
            )
        }
        callback(Result.success(message))
        return true
    }

    // -------------------------------------------------------------------------
    // Headless operations (hold capture/release, recurring charge)
    // -------------------------------------------------------------------------

    /**
     * Runs a [PaymentAction] call and resolves [callback] exactly once.
     *
     * `PaymentAction` reports through a `StateFlow` seeded with `PayActionIdle`
     * that never completes, so the collector skips that placeholder and cancels
     * itself as soon as a real state arrives.
     */
    private fun runPaymentAction(
        request: RkPaymentRequest,
        callback: (Result<Boolean>) -> Unit,
        start: (PaymentAction, PaymentParams) -> Unit
    ) {
        val params = try {
            request.toPaymentParams()
        } catch (error: Throwable) {
            callback(Result.failure(FlutterError(ERROR_NATIVE, error.message ?: "$error")))
            return
        }

        val action = PaymentAction.init()
        var settled = false
        var job: Job? = null
        job = scope.launch {
            action.state.collect { state ->
                if (settled) return@collect
                val success = when (state) {
                    is PayActionState -> state.success
                    is PayRecurrentState -> state.success
                    // PayActionIdle — the seed value, not an answer yet.
                    else -> return@collect
                }
                settled = true
                callback(Result.success(success))
                job?.cancel()
            }
        }
        start(action, params)
    }

    // -------------------------------------------------------------------------
    // Transport records -> Robokassa SDK models
    // -------------------------------------------------------------------------

    private fun RkPaymentRequest.toPaymentParams(): PaymentParams {
        val request = this
        // `mode` is never read below — the Dart side bakes the same signal into the
        // order flags — so assert the two agree rather than let them silently drift.
        when (mode) {
            RkPaymentMode.HOLD -> require(request.order.isHold) {
                "mode=HOLD but order.isHold is false"
            }
            RkPaymentMode.RECURRENT -> require(request.order.isRecurrent) {
                "mode=RECURRENT but order.isRecurrent is false"
            }
            RkPaymentMode.SAVED_CARD -> require(!request.order.token.isNullOrEmpty()) {
                "mode=SAVED_CARD but order.token is empty"
            }
            RkPaymentMode.SIMPLE -> Unit
        }
        return PaymentParams().apply {
            order = OrderParams().apply {
                orderSum = request.order.orderSum
                // The SDK treats a non-positive id as "let Robokassa allocate".
                invoiceId = request.order.invoiceId.toInvoiceId("invoiceId")
                previousInvoiceId =
                    request.order.previousInvoiceId.toInvoiceId("previousInvoiceId")
                description = request.order.orderDescription
                incCurrLabel = request.order.incCurrLabel
                token = request.order.token
                isRecurrent = request.order.isRecurrent
                isHold = request.order.isHold
                outSumCurrency = request.order.outSumCurrency?.let(::toCurrency)
                expirationDate = request.order.expirationDateEpochMs?.let { Date(it) }
                receipt = request.order.receipt?.let(::toReceipt)
            }
            customer = CustomerParams().apply {
                culture = request.customer.culture?.let(::toCulture)
                email = request.customer.email
                ip = request.customer.ip
            }
            view = ViewParams().apply {
                hasToolbar = request.view.hasToolbar
                toolbarBgColor = request.view.toolbarBgColor
                toolbarTextColor = request.view.toolbarTextColor
                toolbarText = request.view.toolbarText
            }
            setCredentials(
                merchantLogin = request.credentials.merchantLogin,
                password1 = request.credentials.password1,
                password2 = request.credentials.password2,
                redirectUrl = request.credentials.redirectUrl
            )
        }
    }

    private fun toReceipt(message: RkReceiptMessage) = Receipt(
        sno = message.sno?.let(::toTaxSystem),
        items = message.items.map { item ->
            ReceiptItem(
                name = item.name,
                // The SDK types `sum` as a non-null Double, so derive the line
                // total when the caller supplied only a unit price.
                sum = item.sum ?: ((item.cost ?: 0.0) * item.quantity),
                quantity = item.quantity.toInt(),
                cost = item.cost,
                nomenclatureCode = item.nomenclatureCode,
                paymentMethod = item.paymentMethod?.let(::toPaymentMethod),
                paymentObject = item.paymentObject?.let(::toPaymentObject),
                tax = item.tax?.let(::toTax)
            )
        }
    )

    private fun toCulture(wire: String) = when (wire.lowercase()) {
        "en", "eng" -> Culture.EN
        else -> Culture.RU
    }

    private fun toCurrency(wire: String) = when (wire.uppercase()) {
        "USD" -> Currency.USD
        "EUR" -> Currency.EUR
        "KZT" -> Currency.KZT
        else -> Currency.RUB
    }

    private fun toTaxSystem(wire: String) = when (wire) {
        "osn" -> TaxSystem.OSN
        "usn_income" -> TaxSystem.USN_INCOME
        "usn_income_outcome" -> TaxSystem.USN_INCOME_OUTCOME
        "esn" -> TaxSystem.ESN
        "patent" -> TaxSystem.PATENT
        else -> throw IllegalArgumentException("Unknown taxation system \"$wire\"")
    }

    private fun toTax(wire: String) = when (wire) {
        "none" -> Tax.NONE
        "vat0" -> Tax.VAT_0
        "vat5" -> Tax.VAT_5
        "vat7" -> Tax.VAT_7
        "vat10" -> Tax.VAT_10
        "vat20" -> Tax.VAT_20
        "vat22" -> Tax.VAT_22
        "vat105" -> Tax.VAT_105
        "vat107" -> Tax.VAT_107
        "vat110" -> Tax.VAT_110
        "vat120" -> Tax.VAT_120
        "vat122" -> Tax.VAT_122
        else -> throw IllegalArgumentException("Unknown VAT rate \"$wire\"")
    }

    private fun toPaymentMethod(wire: String) = when (wire) {
        "full_prepayment" -> PaymentMethod.FULL_PREPAYMENT
        "prepayment" -> PaymentMethod.PREPAYMENT
        "advance" -> PaymentMethod.ADVANCE
        "full_payment" -> PaymentMethod.FULL_PAYMENT
        "partial_payment" -> PaymentMethod.PARTIAL_PAYMENT
        "credit" -> PaymentMethod.CREDIT
        "credit_payment" -> PaymentMethod.CREDIT_PAYMENT
        else -> throw IllegalArgumentException("Unknown settlement method \"$wire\"")
    }

    private fun toPaymentObject(wire: String) = when (wire) {
        "commodity" -> PaymentObject.COMMODITY
        "excise" -> PaymentObject.EXCISE
        "job" -> PaymentObject.JOB
        "service" -> PaymentObject.SERVICE
        "gambling_bet" -> PaymentObject.GAMBLING_BET
        "gambling_prize" -> PaymentObject.GAMBLING_PRIZE
        "lottery" -> PaymentObject.LOTTERY
        "lottery_prize" -> PaymentObject.LOTTERY_PRIZE
        "intellectual_activity" -> PaymentObject.INTELLECTUAL_ACTIVITY
        "payment" -> PaymentObject.PAYMENT
        "agent_commission" -> PaymentObject.AGENT_COMMISSION
        "composite" -> PaymentObject.COMPOSITE
        "resort_fee" -> PaymentObject.RESORT_FEE
        "another" -> PaymentObject.ANOTHER
        "property_right" -> PaymentObject.PROPERTY_RIGHT
        "operating_gain" -> PaymentObject.NON_OPERATING_GAIN
        "insurance_premium" -> PaymentObject.INSURANCE_PREMIUM
        "sales_tax" -> PaymentObject.SALES_TAX
        else -> throw IllegalArgumentException("Unknown settlement subject \"$wire\"")
    }
}

/**
 * Narrows a 64-bit wire invoice id to the native SDK's `Int` field.
 *
 * `null` means "let Robokassa allocate", which the SDK spells as a non-positive
 * id. An out-of-range value throws rather than silently wrapping into a
 * different — possibly valid — invoice.
 */
private fun Long?.toInvoiceId(field: String): Int {
    if (this == null) return -1
    require(this in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) {
        "$field $this does not fit in the 32-bit id Robokassa's Android SDK accepts"
    }
    return toInt()
}
