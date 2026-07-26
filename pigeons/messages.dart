// Pigeon schema for the Robokassa native bridge.
//
// Regenerate after editing:
//   fvm dart run pigeon --input pigeons/messages.dart
//
// Everything crossing the channel is a plain transport record — the rich Dart
// types in `lib/src/models` convert into these in `robokassa_platform.dart`.
// Enum-valued fields travel as their Robokassa **wire** strings (`vat10`,
// `full_payment`, …) rather than as Pigeon enums, so that adding a value to
// the fiscal catalogue does not require regenerating three languages.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/platform/messages.g.dart',
    dartOptions: DartOptions(),
    // Generates `TestRobokassaHostApi`, which installs mock channel handlers
    // so tests assert on what actually crosses the bridge — encoded and
    // decoded by the real Pigeon codec, not by a hand-written fake that could
    // drift from it. Pigeon 27 deprecates this in favour of faking the
    // generated Dart API, which would skip the codec entirely; for a payments
    // bridge the round-trip is worth more than the lint.
    // ignore: deprecated_member_use
    dartTestOut: 'test/platform/test_api.g.dart',
    kotlinOut:
        'android/src/main/kotlin/ru/robokassa/robokassa_sdk/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'ru.robokassa.robokassa_sdk'),
    swiftOut: 'ios/robokassa_sdk/Sources/robokassa_sdk/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'robokassa_sdk',
  ),
)
/// Which checkout flow the native SDK should run.
enum RkPaymentMode {
  /// Ordinary one-stage payment.
  simple,

  /// Two-stage payment: authorise and hold, capture later.
  hold,

  /// First payment of a recurring series; the card is remembered.
  recurrent,

  /// Payment reusing a card saved by an earlier operation (`token`).
  savedCard,
}

/// How the native checkout screen finished.
enum RkPaymentOutcome {
  /// Payment reached a successful terminal state.
  success,

  /// The user dismissed the checkout screen.
  canceled,

  /// The flow failed; see `errorMessage`.
  error,
}

/// Shop identity and passwords, as the native SDKs want them.
class RkCredentialsMessage {
  RkCredentialsMessage({
    required this.merchantLogin,
    required this.password1,
    required this.password2,
    required this.isTest,
    required this.redirectUrl,
  });

  String merchantLogin;
  String password1;

  /// The native SDKs require password #2 on the device to poll payment state.
  String password2;
  bool isTest;

  /// Success-redirect URL configured for the shop; the Android SDK watches for
  /// it to detect that checkout finished.
  String redirectUrl;
}

/// One fiscal receipt line.
class RkReceiptItemMessage {
  RkReceiptItemMessage({
    required this.name,
    required this.quantity,
    this.sum,
    this.cost,
    this.nomenclatureCode,
    this.paymentMethod,
    this.paymentObject,
    this.tax,
  });

  String name;

  /// Integral quantities only — both native SDKs type this as `Int`.
  int quantity;
  double? sum;
  double? cost;
  String? nomenclatureCode;

  /// `payment_method` wire value, e.g. `full_payment`.
  String? paymentMethod;

  /// `payment_object` wire value, e.g. `commodity`.
  String? paymentObject;

  /// `tax` wire value, e.g. `vat20`.
  String? tax;
}

/// Fiscal receipt attached to a payment.
class RkReceiptMessage {
  RkReceiptMessage({required this.items, this.sno});

  /// `sno` wire value, e.g. `usn_income`.
  String? sno;
  List<RkReceiptItemMessage> items;
}

/// Order details.
class RkOrderMessage {
  RkOrderMessage({
    required this.orderSum,
    required this.isRecurrent,
    required this.isHold,
    this.invoiceId,
    this.previousInvoiceId,
    this.orderDescription,
    this.incCurrLabel,
    this.token,
    this.outSumCurrency,
    this.expirationDateEpochMs,
    this.receipt,
  });

  double orderSum;
  bool isRecurrent;
  bool isHold;
  int? invoiceId;
  int? previousInvoiceId;

  /// `Description` — named `orderDescription` because Pigeon reserves
  /// `description` for Swift's `NSObject.description`.
  String? orderDescription;
  String? incCurrLabel;

  /// `OpKey` of the operation whose saved card should be charged.
  String? token;

  /// `OutSumCurrency` wire value, e.g. `USD`.
  String? outSumCurrency;

  /// `ExpirationDate` as milliseconds since the Unix epoch, UTC.
  int? expirationDateEpochMs;
  RkReceiptMessage? receipt;
}

/// Payer details.
class RkCustomerMessage {
  RkCustomerMessage({this.culture, this.email, this.ip});

  /// `Culture` wire value: `ru` or `en`.
  String? culture;
  String? email;
  String? ip;
}

/// Native checkout screen appearance.
class RkViewMessage {
  RkViewMessage({
    required this.hasToolbar,
    this.toolbarBgColor,
    this.toolbarTextColor,
    this.toolbarText,
  });

  bool hasToolbar;
  String? toolbarBgColor;
  String? toolbarTextColor;
  String? toolbarText;
}

/// A complete native operation request.
class RkPaymentRequest {
  RkPaymentRequest({
    required this.mode,
    required this.credentials,
    required this.order,
    required this.customer,
    required this.view,
  });

  RkPaymentMode mode;
  RkCredentialsMessage credentials;
  RkOrderMessage order;
  RkCustomerMessage customer;
  RkViewMessage view;
}

/// Result of a native checkout screen.
class RkPaymentResultMessage {
  RkPaymentResultMessage({
    required this.outcome,
    this.invoiceId,
    this.opKey,
    this.resultCode,
    this.stateCode,
    this.stateDescription,
    this.errorMessage,
  });

  RkPaymentOutcome outcome;
  int? invoiceId;

  /// Operation key — pass it back as `order.token` to charge the saved card.
  String? opKey;

  /// `<Result><Code>` value, e.g. `0`.
  String? resultCode;

  /// `<State><Code>` value, e.g. `100`.
  String? stateCode;

  /// Robokassa's own message, usually Russian. Named `stateDescription`
  /// because Pigeon reserves `description` for Swift's `NSObject.description`.
  String? stateDescription;
  String? errorMessage;
}

/// Operations implemented by the native Robokassa SDKs.
// ignore: deprecated_member_use — see the note on `dartTestOut` above.
@HostApi(dartHostTestHandler: 'TestRobokassaHostApi')
abstract class RobokassaHostApi {
  /// Opens the native checkout screen and completes when it closes.
  @async
  RkPaymentResultMessage startPayment(RkPaymentRequest request);

  /// Captures a previously held payment.
  @async
  bool confirmHold(RkPaymentRequest request);

  /// Releases a previously held payment.
  @async
  bool cancelHold(RkPaymentRequest request);

  /// Charges a recurring payment against `order.previousInvoiceId`.
  @async
  bool chargeRecurring(RkPaymentRequest request);

  /// Queries the state of `order.invoiceId` without showing any UI.
  @async
  RkPaymentResultMessage checkPaymentState(RkPaymentRequest request);

  /// Whether the native Robokassa SDK is actually linked into this build.
  ///
  /// Lets an app fail with a useful message instead of a `ClassNotFound`
  /// crash when the consumer-side native setup was skipped.
  bool isNativeSdkAvailable();
}
