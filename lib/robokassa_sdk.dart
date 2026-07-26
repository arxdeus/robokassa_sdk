/// Robokassa payments for Flutter.
///
/// Three layers, usable together or separately:
///
/// * `Robokassa` — the facade. Native 3-D Secure checkout on Android and iOS,
///   backed by Robokassa's official SDKs.
/// * `RobokassaLinkBuilder` / `RobokassaSignature` — pure-Dart signing and
///   payment-link construction that runs anywhere, including tests and
///   server-side Dart.
/// * `RobokassaApi` — direct HTTP access to the merchant interfaces
///   (payment state, hold capture/release, recurring charges).
///
/// See the README for the consumer-side native setup both platforms require.
library;

export 'src/api/robokassa_api.dart'
    show CreatedInvoice, RobokassaApi, RobokassaApiException;
export 'src/api/state_xml.dart' show parseOperationStateXml;
export 'src/core/amount.dart'
    show formatExpirationDate, formatOutSum, parseOutSum;
export 'src/core/callbacks.dart' show RobokassaCallback, RobokassaCallbackKind;
export 'src/core/credentials.dart' show RobokassaCredentials;
export 'src/core/endpoints.dart';
export 'src/core/hash_algorithm.dart' show HashAlgorithm, constantTimeEquals;
export 'src/core/payment_link.dart'
    show RobokassaLinkBuilder, buildRobokassaPaymentLink, encodeFormBody;
export 'src/core/receipt_encoding.dart' show ReceiptSignatureMode;
export 'src/core/signature.dart' show RobokassaSignature;
export 'src/core/user_parameters.dart'
    show
        UserParameters,
        isUserParameterName,
        kUserParameterPrefix,
        normalizeUserParameterName;
export 'src/models/enums.dart'
    show Culture, Currency, PaymentMethod, PaymentObject, Tax, TaxSystem;
export 'src/models/payment_params.dart'
    show CustomerParams, OrderParams, PaymentParams, ViewParams;
export 'src/models/payment_result.dart'
    show PaymentOutcome, RobokassaNativeException, RobokassaPaymentResult;
export 'src/models/payment_state.dart'
    show PaymentState, PaymentStateCode, RequestResultCode;
export 'src/models/receipt.dart' show Receipt, ReceiptItem, formatReceiptAmount;
export 'src/platform/robokassa_platform.dart'
    show PigeonRobokassaPlatform, RobokassaPaymentMode, RobokassaPlatform;
export 'src/robokassa.dart' show Robokassa;
