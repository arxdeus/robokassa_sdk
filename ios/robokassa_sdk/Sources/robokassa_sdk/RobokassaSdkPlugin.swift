import Flutter
import UIKit

/// Bridges Flutter to Robokassa's official iOS SDK.
///
/// That SDK is vendored into this same module under `RobokassaSDK/` rather than
/// linked as a separate pod, so there is no `import RobokassaSDK` — see
/// `RobokassaSDK/VENDORED.md`.
///
/// The SDK's `Robokassa` class presents its own `WebViewController` on top of
/// whatever is frontmost — under Flutter that is the `FlutterViewController` —
/// and reports through three closures. Those closures are *not* one-shot:
/// while the SDK polls the payment-state service it calls `onFailureHandler`
/// repeatedly for transient "not paid yet" answers, and it dismisses the screen
/// a couple of seconds after a terminal answer. Each flow is therefore wrapped
/// in a `PaymentSession` that settles its Pigeon callback exactly once and
/// remembers the last failure so a later dismissal can be classified.
public class RobokassaSdkPlugin: NSObject, FlutterPlugin, RobokassaHostApi {

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = RobokassaSdkPlugin()
    RobokassaHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    registrar.publish(instance)
  }

  /// The in-flight checkout, retained so the SDK object outlives this call.
  private var session: PaymentSession?

  // ---------------------------------------------------------------------------
  // RobokassaHostApi
  // ---------------------------------------------------------------------------

  public func isNativeSdkAvailable() throws -> Bool {
    // The SDK is compiled into this module, so it cannot be absent.
    return true
  }

  public func startPayment(
    request: RkPaymentRequest,
    completion: @escaping (Result<RkPaymentResultMessage, Error>) -> Void
  ) {
    guard session == nil else {
      completion(.failure(PigeonError(
        code: "busy",
        message: "A Robokassa checkout is already in progress. Await the first "
          + "call before starting another.",
        details: nil)))
      return
    }

    if request.mode == .savedCard, (request.order.token ?? "").isEmpty {
      completion(.failure(PigeonError(
        code: "invalid_arguments",
        message: "A saved-card payment needs `order.token` — the opKey of the "
          + "earlier payment that saved the card.",
        details: nil)))
      return
    }

    let params: PaymentParams
    do {
      params = try RobokassaSdkPlugin.makePaymentParams(request)
    } catch {
      completion(.failure(error))
      return
    }

    let robokassa = Robokassa(
      login: request.credentials.merchantLogin,
      password: request.credentials.password1,
      password2: request.credentials.password2,
      isTesting: request.credentials.isTest)

    // Asked for on the success path so the result carries Robokassa's real
    // `<Result><Code>`/`<State><Code>`, as the Android SDK's success already
    // does. Skipped without an invoice: `checkPaymentParams` omits `invoiceID`
    // then, and the service has nothing to answer for.
    let checkBody = params.order.invoiceId > 0
      ? RobokassaSdkPlugin.makeCheckStatusBody(request, params)
      : nil

    let session = PaymentSession(
      robokassa: robokassa,
      invoiceId: request.order.invoiceId,
      checkBody: checkBody
    ) { [weak self] result in
      self?.session = nil
      completion(.success(result))
    }
    self.session = session
    session.attachHandlers()

    switch request.mode {
    case .simple:
      robokassa.startSimplePayment(with: params)
    case .hold:
      robokassa.startHoldingPayment(with: params)
    case .recurrent:
      robokassa.startDefaultReccurentPayment(with: params)
    case .savedCard:
      robokassa.startPaymentBySavedCard(with: params)
    }
  }

  public func confirmHold(
    request: RkPaymentRequest,
    completion: @escaping (Result<Bool, Error>) -> Void
  ) {
    run(request, completion) { robokassa, params, done in
      robokassa.confirmHoldingPayment(with: params, completion: done)
    }
  }

  public func cancelHold(
    request: RkPaymentRequest,
    completion: @escaping (Result<Bool, Error>) -> Void
  ) {
    run(request, completion) { robokassa, params, done in
      robokassa.cancelHoldingPayment(with: params, completion: done)
    }
  }

  public func chargeRecurring(
    request: RkPaymentRequest,
    completion: @escaping (Result<Bool, Error>) -> Void
  ) {
    guard let previous = request.order.previousInvoiceId, previous > 0 else {
      completion(.failure(PigeonError(
        code: "invalid_arguments",
        message: "chargeRecurring needs `order.previousInvoiceId` — the invoice "
          + "of the first, already-paid payment in the series.",
        details: nil)))
      return
    }
    run(request, completion) { robokassa, params, done in
      robokassa.startReccurentPayment(with: params, completion: done)
    }
  }

  public func checkPaymentState(
    request: RkPaymentRequest,
    completion: @escaping (Result<RkPaymentResultMessage, Error>) -> Void
  ) {
    // Deliberately *not* routed through the SDK's `ServiceCheckPaymentStatus`,
    // whose `checkPaymentStatus()` rebuilds its request body from a
    // `UserDefaults` key written by the last checkout — it would answer for
    // whichever invoice was paid most recently, not the one asked about, and a
    // wrong payment status is worse than no status. Its transport underneath,
    // `RequestManager.requestForCheckStatus`, takes the body as an argument and
    // has no such coupling, so this builds the body from *this* request and
    // calls that directly.
    let params: PaymentParams
    do {
      params = try RobokassaSdkPlugin.makePaymentParams(request)
    } catch {
      completion(.failure(error))
      return
    }

    // Both hoisted so the task below closes over nothing but `Sendable` values.
    let body = RobokassaSdkPlugin.makeCheckStatusBody(request, params)
    let invoiceId = request.order.invoiceId

    Task { @MainActor in
      do {
        let codes = try await RobokassaSdkPlugin.queryStateCodes(body: body)
        completion(.success(RobokassaSdkPlugin.makeStateResult(
          invoiceId: invoiceId,
          resultCode: codes.result,
          stateCode: codes.state)))
      } catch {
        completion(.failure(PigeonError(
          code: "robokassa_native_error",
          message: error.localizedDescription,
          details: nil)))
      }
    }
  }

  /// The `MerchantLogin:invoiceID:Password2` body for *this* request's invoice.
  ///
  /// `checkPaymentParams` signs with password #2, which the SDK's own entry
  /// points inject; reaching the transport directly means doing it here.
  fileprivate static func makeCheckStatusBody(
    _ request: RkPaymentRequest,
    _ params: PaymentParams
  ) -> String {
    var query = params
    query.merchantLogin = request.credentials.merchantLogin
    query.password2 = request.credentials.password2
    return query.checkPaymentParams
  }

  /// Robokassa's `<Result><Code>` and `<State><Code>` from one `OpStateExt` answer.
  fileprivate struct StateCodes {
    let result: String?
    let state: String?
  }

  /// Queries the payment-state service for `body`, bounded by a timeout.
  ///
  /// The bound matters: this also runs on the checkout's success path, where
  /// `URLSession`'s own 60s default would leave the Dart `await` pending long
  /// after the user is back in the app.
  fileprivate static func queryStateCodes(
    body: String,
    timeoutNanoseconds: UInt64 = 15_000_000_000
  ) async throws -> StateCodes {
    try await withThrowingTaskGroup(of: StateCodes?.self) { group in
      // `RequestManager.shared` is main-actor isolated.
      group.addTask { @MainActor in
        let xml = try await RequestManager.shared.requestForCheckStatus(to: body)
        return StateCodes(
          result: RequestManager.shared.getStateCode(from: xml, "Result"),
          state: RequestManager.shared.getStateCode(from: xml, "State"))
      }
      group.addTask {
        try await Task.sleep(nanoseconds: timeoutNanoseconds)
        return nil
      }
      // Whichever finishes first wins; the loser is cancelled and its result
      // discarded as the group drains on the way out.
      defer { group.cancelAll() }
      guard let codes = try await group.next() ?? nil else {
        throw MessagedError(
          message: "Timed out waiting for the Robokassa payment-state service.")
      }
      return codes
    }
  }

  /// Classifies an `OpStateExt` `<Result><Code>` / `<State><Code>` pair, matching
  /// how the Dart fallback maps the same endpoint.
  private static func makeStateResult(
    invoiceId: Int64?,
    resultCode: String?,
    stateCode: String?
  ) -> RkPaymentResultMessage {
    guard resultCode == "0" else {
      // Robokassa refused the query itself (bad signature, unknown invoice, …);
      // there is no payment state to report.
      let reason = PaymentResult(rawValue: resultCode ?? "") ?? .notFound
      return RkPaymentResultMessage(
        outcome: .error,
        invoiceId: invoiceId,
        resultCode: resultCode,
        stateDescription: reason.title,
        errorMessage: reason.title)
    }

    let state = PaymentState(rawValue: stateCode ?? "") ?? .notFound
    let outcome: RkPaymentOutcome
    switch state {
    case .paymentSuccess, .holdSuccess:
      outcome = .success
    case .cancelledNotPaid:
      outcome = .canceled
    default:
      outcome = .error
    }

    return RkPaymentResultMessage(
      outcome: outcome,
      invoiceId: invoiceId,
      resultCode: resultCode,
      stateCode: stateCode,
      stateDescription: state.title,
      errorMessage: outcome == .error ? state.title : nil)
  }

  // ---------------------------------------------------------------------------
  // Headless operations
  // ---------------------------------------------------------------------------

  /// Shared plumbing for the three completion-handler operations.
  private func run(
    _ request: RkPaymentRequest,
    _ completion: @escaping (Result<Bool, Error>) -> Void,
    _ body: (Robokassa, PaymentParams, @escaping (Result<Bool, Error>) -> Void) -> Void
  ) {
    let params: PaymentParams
    do {
      params = try RobokassaSdkPlugin.makePaymentParams(request)
    } catch {
      completion(.failure(error))
      return
    }

    let robokassa = Robokassa(
      login: request.credentials.merchantLogin,
      password: request.credentials.password1,
      password2: request.credentials.password2,
      isTesting: request.credentials.isTest)

    // Capture `robokassa` in the closure so it outlives this scope; the SDK
    // keeps no strong reference to itself while the request is in flight.
    body(robokassa, params) { result in
      withExtendedLifetime(robokassa) {
        switch result {
        case .success(let value):
          completion(.success(value))
        case .failure(let error):
          completion(.failure(PigeonError(
            code: "robokassa_native_error",
            message: error.localizedDescription,
            details: nil)))
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Transport records -> Robokassa SDK models
  // ---------------------------------------------------------------------------

  private static func makePaymentParams(_ request: RkPaymentRequest) throws -> PaymentParams {
    // Hoisted so the `try` covers a whole statement rather than sitting inside
    // an argument list.
    let receipt = try makeReceipt(request.order.receipt)

    // Rejected rather than dropped: silently nilling an unrecognised currency
    // would charge the merchant's default one instead, which a caller could
    // only discover from their settlement report.
    var outSumCurrency: Currency?
    if let raw = request.order.outSumCurrency {
      guard let parsed = Currency(rawValue: raw.lowercased()) else {
        throw PigeonError(
          code: "invalid_arguments",
          message: "Unknown settlement currency \"\(raw)\".",
          details: nil)
      }
      outSumCurrency = parsed
    }

    var order = OrderParams(
      invoiceId: Int(request.order.invoiceId ?? -1),
      orderSum: request.order.orderSum,
      description: request.order.orderDescription,
      incCurrLabel: request.order.incCurrLabel,
      token: request.order.token,
      outSumCurrency: outSumCurrency,
      expirationDate: request.order.expirationDateEpochMs.map {
        Date(timeIntervalSince1970: TimeInterval($0) / 1000.0)
      },
      receipt: receipt)

    // Not covered by `OrderParams.init`, but public and settable.
    order.previousInvoiceId = Int(request.order.previousInvoiceId ?? -1)
    order.isRecurrent = request.order.isRecurrent
    order.isHold = request.order.isHold

    // The SDK spells English `eng`, so `en` has to be translated. Anything else
    // is rejected rather than coerced to English — a typo used to change the
    // checkout language with no diagnostic.
    var culture: Culture?
    if let raw = request.customer.culture {
      switch raw.lowercased() {
      case "ru": culture = .ru
      case "en", "eng": culture = .eng
      default:
        throw PigeonError(
          code: "invalid_arguments",
          message: "Unknown checkout language \"\(raw)\"; expected \"ru\" or \"en\".",
          details: nil)
      }
    }

    let customer = CustomerParams(
      culture: culture,
      email: request.customer.email,
      ip: request.customer.ip)

    let view = ViewParams(
      toolbarBgColor: request.view.toolbarBgColor,
      toolbarTextColor: request.view.toolbarTextColor,
      toolbarText: request.view.toolbarText,
      hasToolbar: request.view.hasToolbar)

    return PaymentParams(order: order, customer: customer, view: view)
  }

  private static func makeReceipt(_ message: RkReceiptMessage?) throws -> Receipt? {
    guard let message else { return nil }

    var sno: TaxSystem?
    if let raw = message.sno {
      guard let parsed = TaxSystem(rawValue: raw) else {
        throw PigeonError(
          code: "invalid_arguments",
          message: "Unknown taxation system \"\(raw)\".",
          details: nil)
      }
      sno = parsed
    }

    let items = try message.items.map { item -> ReceiptItem in
      var tax: Tax?
      if let raw = item.tax {
        guard let parsed = Tax(rawValue: raw) else {
          throw PigeonError(
            code: "invalid_arguments",
            message: "Unknown VAT rate \"\(raw)\" on receipt line \"\(item.name)\".",
            details: nil)
        }
        tax = parsed
      }
      var paymentMethod: PaymentMethod?
      if let raw = item.paymentMethod {
        guard let parsed = PaymentMethod(rawValue: raw) else {
          throw PigeonError(
            code: "invalid_arguments",
            message: "Unknown settlement method \"\(raw)\" on line \"\(item.name)\".",
            details: nil)
        }
        paymentMethod = parsed
      }
      var paymentObject: PaymentObject?
      if let raw = item.paymentObject {
        guard let parsed = PaymentObject(rawValue: raw) else {
          throw PigeonError(
            code: "invalid_arguments",
            message: "Unknown settlement subject \"\(raw)\" on line \"\(item.name)\".",
            details: nil)
        }
        paymentObject = parsed
      }

      // The SDK types `sum` as a non-optional Double, so derive the line total
      // when the caller supplied only a unit price.
      let quantity = Int(item.quantity)
      let sum = item.sum ?? ((item.cost ?? 0) * Double(quantity))

      return ReceiptItem(
        name: item.name,
        sum: sum,
        quantity: quantity,
        cost: item.cost,
        nomenclatureCode: item.nomenclatureCode,
        paymentMethod: paymentMethod,
        paymentObject: paymentObject,
        tax: tax)
    }

    return Receipt(sno: sno, items: items)
  }
}

/// Collapses the Robokassa SDK's repeat-firing closures into one answer.
private final class PaymentSession {
  private let robokassa: Robokassa
  private let invoiceId: Int64?
  /// Signed `OpStateExt` body for this invoice, or nil if there is none to ask about.
  private let checkBody: String?
  private let finish: (RkPaymentResultMessage) -> Void

  private var settled = false
  private var lastFailure: String?

  init(
    robokassa: Robokassa,
    invoiceId: Int64?,
    checkBody: String?,
    finish: @escaping (RkPaymentResultMessage) -> Void
  ) {
    self.robokassa = robokassa
    self.invoiceId = invoiceId
    self.checkBody = checkBody
    self.finish = finish
  }

  func attachHandlers() {
    robokassa.onSuccessHandler = { [weak self] opKey in
      guard let self, !self.settled else { return }
      // Set *before* the query below, on the same main-thread turn as the
      // guard: the SDK's handlers fire again while it is in flight, and this
      // flag is the only thing making those calls no-ops.
      self.settled = true
      // The SDK's success closure carries nothing but an opaque opKey, so
      // Robokassa's documented `<Result><Code>`/`<State><Code>` — which the
      // Android SDK surfaces on its own success — are read from the
      // payment-state service here. They stay nil if that query fails or times
      // out: a failed *status lookup* must not demote a payment that actually
      // succeeded.
      Task { @MainActor in
        var codes: RobokassaSdkPlugin.StateCodes?
        if let body = self.checkBody {
          do {
            codes = try await RobokassaSdkPlugin.queryStateCodes(body: body)
          } catch {
            print("Robokassa: payment succeeded but its state query failed; "
              + "resultCode/stateCode will be nil. \(error.localizedDescription)")
          }
        }
        self.finish(RkPaymentResultMessage(
          outcome: .success,
          invoiceId: self.invoiceId,
          opKey: opKey,
          resultCode: codes?.result,
          stateCode: codes?.state))
      }
    }

    robokassa.onFailureHandler = { [weak self] reason in
      // Fires repeatedly for transient "not paid yet" polls, so it only
      // records the reason; the dismissal below decides the outcome.
      guard let self, !self.settled else { return }
      self.lastFailure = reason
    }

    robokassa.onDimissHandler = { [weak self] in
      guard let self, !self.settled else { return }
      self.settled = true
      if let failure = self.lastFailure {
        self.finish(RkPaymentResultMessage(
          outcome: .error,
          invoiceId: self.invoiceId,
          errorMessage: failure))
      } else {
        self.finish(RkPaymentResultMessage(
          outcome: .canceled,
          invoiceId: self.invoiceId))
      }
    }
  }
}
