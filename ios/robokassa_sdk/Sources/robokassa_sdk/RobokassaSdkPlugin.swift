import Flutter
import UIKit
import RobokassaSDK

/// Bridges Flutter to Robokassa's official iOS SDK.
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
    // Reaching this line means `import RobokassaSDK` linked successfully.
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

    let session = PaymentSession(
      robokassa: robokassa,
      invoiceId: request.order.invoiceId,
      isHold: request.mode == .hold
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
    // Robokassa's iOS SDK exposes no headless state query that exists in both
    // its CocoaPods and SwiftPM layouts: the pod-only
    // `ServiceCheckPaymentStatus` reads its parameters from `UserDefaults`
    // written by a previous checkout, so it cannot answer for an arbitrary
    // invoice. Dart recognises this code and falls back to
    // `RobokassaApi.getPaymentState`, which calls the same `OpStateExt`
    // endpoint and returns strictly more detail.
    completion(.failure(PigeonError(
      code: "unsupported_on_ios",
      message: "Native payment-state queries are unavailable on iOS; "
        + "robokassa_sdk falls back to its Dart implementation.",
      details: nil)))
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

    var order = OrderParams(
      invoiceId: Int(request.order.invoiceId ?? -1),
      orderSum: request.order.orderSum,
      description: request.order.orderDescription,
      incCurrLabel: request.order.incCurrLabel,
      token: request.order.token,
      outSumCurrency: request.order.outSumCurrency.flatMap {
        Currency(rawValue: $0.lowercased())
      },
      expirationDate: request.order.expirationDateEpochMs.map {
        Date(timeIntervalSince1970: TimeInterval($0) / 1000.0)
      },
      receipt: receipt)

    // Not covered by `OrderParams.init`, but public and settable.
    order.previousInvoiceId = Int(request.order.previousInvoiceId ?? -1)
    order.isRecurrent = request.order.isRecurrent
    order.isHold = request.order.isHold

    // Annotated rather than inferred: inside a closure the implicit members
    // `.ru` / `.eng` have no contextual base for the compiler to resolve.
    let culture: Culture? = request.customer.culture.map { raw -> Culture in
      // The SDK spells English `eng`, so `en` has to be translated.
      raw.lowercased() == "ru" ? Culture.ru : Culture.eng
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
  private let isHold: Bool
  private let finish: (RkPaymentResultMessage) -> Void

  private var settled = false
  private var lastFailure: String?

  init(
    robokassa: Robokassa,
    invoiceId: Int64?,
    isHold: Bool,
    finish: @escaping (RkPaymentResultMessage) -> Void
  ) {
    self.robokassa = robokassa
    self.invoiceId = invoiceId
    self.isHold = isHold
    self.finish = finish
  }

  func attachHandlers() {
    robokassa.onSuccessHandler = { [weak self] opKey in
      guard let self, !self.settled else { return }
      self.settled = true
      self.finish(RkPaymentResultMessage(
        outcome: .success,
        invoiceId: self.invoiceId,
        opKey: opKey,
        resultCode: "0",
        // A successful hold rests in state 20, an ordinary payment in 100.
        stateCode: self.isHold ? "20" : "100"))
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
