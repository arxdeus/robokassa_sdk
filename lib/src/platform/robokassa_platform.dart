import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../core/credentials.dart';
import '../models/payment_params.dart';
import '../models/payment_result.dart';
import '../models/payment_state.dart';
import '../models/receipt.dart';
import 'messages.g.dart';

/// Which native checkout flow to run.
enum RobokassaPaymentMode {
  /// Ordinary one-stage payment.
  simple,

  /// Two-stage payment: authorise and hold funds, capture later.
  hold,

  /// First payment of a recurring series; Robokassa remembers the card.
  recurrent,

  /// Payment reusing a card saved by an earlier operation.
  ///
  /// Requires `OrderParams.token` — the `opKey` from that operation.
  savedCard,
}

/// The surface the Robokassa plugin exposes to the platform side.
///
/// Extend this and assign [RobokassaPlatform.instance] to fake the native
/// layer in widget tests without touching method channels.
abstract class RobokassaPlatform extends PlatformInterface {
  /// Creates a platform implementation.
  RobokassaPlatform() : super(token: _token);

  static final Object _token = Object();

  static RobokassaPlatform _instance = PigeonRobokassaPlatform();

  /// The active implementation. Defaults to the Pigeon channel bridge.
  static RobokassaPlatform get instance => _instance;

  /// Replaces the active implementation.
  static set instance(RobokassaPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Opens the native checkout screen; completes when it closes.
  Future<RobokassaPaymentResult> startPayment({
    required RobokassaCredentials credentials,
    required PaymentParams params,
    required RobokassaPaymentMode mode,
  });

  /// Captures a previously held payment.
  Future<bool> confirmHold({
    required RobokassaCredentials credentials,
    required PaymentParams params,
  });

  /// Releases a previously held payment.
  Future<bool> cancelHold({
    required RobokassaCredentials credentials,
    required PaymentParams params,
  });

  /// Charges a recurring payment against `order.previousInvoiceId`.
  Future<bool> chargeRecurring({
    required RobokassaCredentials credentials,
    required PaymentParams params,
  });

  /// Queries payment state without showing UI.
  Future<RobokassaPaymentResult> checkPaymentState({
    required RobokassaCredentials credentials,
    required PaymentParams params,
  });

  /// Whether the native Robokassa SDK is linked into this build.
  Future<bool> isNativeSdkAvailable();
}

/// The default [RobokassaPlatform], talking to the native SDKs over Pigeon.
class PigeonRobokassaPlatform extends RobokassaPlatform {
  /// Creates the bridge.
  ///
  /// [api] is injectable so tests can supply a generated mock.
  PigeonRobokassaPlatform({RobokassaHostApi? api})
    : _api = api ?? RobokassaHostApi();

  final RobokassaHostApi _api;

  @override
  Future<RobokassaPaymentResult> startPayment({
    required RobokassaCredentials credentials,
    required PaymentParams params,
    required RobokassaPaymentMode mode,
  }) => _guard(
    () async => _toResult(
      await _api.startPayment(_toRequest(credentials, params, mode)),
    ),
  );

  @override
  Future<bool> confirmHold({
    required RobokassaCredentials credentials,
    required PaymentParams params,
  }) => _guard(
    () => _api.confirmHold(
      _toRequest(credentials, params, RobokassaPaymentMode.hold),
    ),
  );

  @override
  Future<bool> cancelHold({
    required RobokassaCredentials credentials,
    required PaymentParams params,
  }) => _guard(
    () => _api.cancelHold(
      _toRequest(credentials, params, RobokassaPaymentMode.hold),
    ),
  );

  @override
  Future<bool> chargeRecurring({
    required RobokassaCredentials credentials,
    required PaymentParams params,
  }) {
    if (params.order.previousInvoiceId == null ||
        params.order.previousInvoiceId! <= 0) {
      throw ArgumentError(
        'chargeRecurring needs `order.previousInvoiceId` — the invoice of the '
        'first, already-paid payment in the series.',
      );
    }
    return _guard(
      () => _api.chargeRecurring(
        _toRequest(credentials, params, RobokassaPaymentMode.recurrent),
      ),
    );
  }

  @override
  Future<RobokassaPaymentResult> checkPaymentState({
    required RobokassaCredentials credentials,
    required PaymentParams params,
  }) => _guard(
    () async => _toResult(
      await _api.checkPaymentState(
        _toRequest(credentials, params, RobokassaPaymentMode.simple),
      ),
    ),
  );

  @override
  Future<bool> isNativeSdkAvailable() async {
    try {
      return await _api.isNativeSdkAvailable();
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Translates channel failures into [RobokassaNativeException].
  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (error) {
      throw RobokassaNativeException(
        error.message ?? 'The native Robokassa SDK reported an error.',
        code: error.code,
        details: error.details,
      );
    } on MissingPluginException {
      throw const RobokassaNativeException(
        'The Robokassa plugin is not registered on this platform. The native '
        'flow supports Android and iOS only; use RobokassaLinkBuilder or '
        'RobokassaApi elsewhere.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Rich models -> transport records
  // ---------------------------------------------------------------------------

  static RkPaymentRequest _toRequest(
    RobokassaCredentials credentials,
    PaymentParams params,
    RobokassaPaymentMode mode,
  ) {
    params.validate();

    if (mode == RobokassaPaymentMode.savedCard &&
        (params.order.token == null || params.order.token!.isEmpty)) {
      throw ArgumentError(
        'A saved-card payment needs `order.token` — the opKey returned by the '
        'earlier payment that saved the card.',
      );
    }

    return RkPaymentRequest(
      mode: switch (mode) {
        RobokassaPaymentMode.simple => RkPaymentMode.simple,
        RobokassaPaymentMode.hold => RkPaymentMode.hold,
        RobokassaPaymentMode.recurrent => RkPaymentMode.recurrent,
        RobokassaPaymentMode.savedCard => RkPaymentMode.savedCard,
      },
      credentials: RkCredentialsMessage(
        merchantLogin: credentials.merchantLogin,
        password1: credentials.password1,
        // Both native SDKs poll the state service themselves, which is signed
        // with password #2, so they cannot run without it.
        password2: credentials.requirePassword2,
        isTest: credentials.isTest,
        redirectUrl: params.redirectUrl ?? '',
      ),
      order: _toOrder(params.order, mode),
      customer: RkCustomerMessage(
        culture: params.customer.culture?.wireValue,
        email: params.customer.email,
        ip: params.customer.ip,
      ),
      view: RkViewMessage(
        hasToolbar: params.view.hasToolbar,
        toolbarBgColor: params.view.toolbarBgColor,
        toolbarTextColor: params.view.toolbarTextColor,
        toolbarText: params.view.toolbarText,
      ),
    );
  }

  static RkOrderMessage _toOrder(OrderParams order, RobokassaPaymentMode mode) {
    return RkOrderMessage(
      orderSum: order.orderSum,
      // The mode is authoritative: asking for a hold flow must set the hold
      // flag even if the caller left `OrderParams.isHold` at its default.
      isHold: order.isHold || mode == RobokassaPaymentMode.hold,
      isRecurrent: order.isRecurrent || mode == RobokassaPaymentMode.recurrent,
      invoiceId: order.invoiceId,
      previousInvoiceId: order.previousInvoiceId,
      orderDescription: order.description,
      incCurrLabel: order.incCurrLabel,
      token: order.token,
      outSumCurrency: order.outSumCurrency?.wireValue,
      expirationDateEpochMs: order.expirationDate?.millisecondsSinceEpoch,
      receipt: order.receipt == null ? null : _toReceipt(order.receipt!),
    );
  }

  static RkReceiptMessage _toReceipt(Receipt receipt) {
    return RkReceiptMessage(
      sno: receipt.sno?.wireValue,
      items: receipt.items.map(_toReceiptItem).toList(growable: false),
    );
  }

  static RkReceiptItemMessage _toReceiptItem(ReceiptItem item) {
    if (item.quantity != item.quantity.roundToDouble()) {
      // Silently truncating would change the fiscal document and break the
      // signature the native SDK computes from it.
      throw ArgumentError.value(
        item.quantity,
        'quantity',
        'The native Robokassa SDKs type receipt quantity as a 32-bit integer, '
            'so "${item.name}" cannot go through the native flow. Use '
            'RobokassaLinkBuilder for fractional quantities.',
      );
    }
    return RkReceiptItemMessage(
      name: item.name,
      quantity: item.quantity.toInt(),
      sum: item.sum,
      cost: item.cost,
      nomenclatureCode: item.nomenclatureCode,
      paymentMethod: item.paymentMethod?.wireValue,
      paymentObject: item.paymentObject?.wireValue,
      tax: item.tax?.wireValue,
    );
  }

  // ---------------------------------------------------------------------------
  // Transport records -> rich models
  // ---------------------------------------------------------------------------

  static RobokassaPaymentResult _toResult(RkPaymentResultMessage message) {
    return RobokassaPaymentResult(
      outcome: switch (message.outcome) {
        RkPaymentOutcome.success => PaymentOutcome.success,
        RkPaymentOutcome.canceled => PaymentOutcome.canceled,
        RkPaymentOutcome.error => PaymentOutcome.error,
      },
      invoiceId: (message.invoiceId != null && message.invoiceId! > 0)
          ? message.invoiceId
          : null,
      opKey: (message.opKey?.isEmpty ?? true) ? null : message.opKey,
      requestResult: RequestResultCode.tryParse(message.resultCode),
      stateCode: PaymentStateCode.tryParse(message.stateCode),
      description: (message.stateDescription?.isEmpty ?? true)
          ? null
          : message.stateDescription,
      errorMessage: (message.errorMessage?.isEmpty ?? true)
          ? null
          : message.errorMessage,
    );
  }
}
