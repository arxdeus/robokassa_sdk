/// Robokassa HTTP endpoints.
///
/// Values are taken from the official SDKs
/// (`Robokassa_Library/.../Constants.kt` and `Robokassa/Network/Constants.swift`)
/// so the Dart core talks to exactly the same hosts as the native flow.
library;

/// Base host for all merchant interfaces.
const String kRobokassaAuthHost = 'auth.robokassa.ru';

/// Payment page. Accepts the parameter set as a `GET` query or a
/// `POST` form body (`application/x-www-form-urlencoded`).
final Uri kPaymentPageUrl = Uri.https(
  kRobokassaAuthHost,
  '/Merchant/Index.aspx',
);

/// Payment page variant that answers with JSON containing an `invoiceID`
/// instead of rendering the checkout form. Used by the iOS SDK to pre-create
/// an invoice before opening the WebView.
final Uri kCreateInvoiceUrl = Uri.https(
  kRobokassaAuthHost,
  '/Merchant/Indexjson.aspx',
);

/// Checkout page for a previously created invoice; the invoice id is appended
/// to this path (`.../Merchant/Index/<invoiceID>`).
final Uri kInvoiceCheckoutBaseUrl = Uri.https(
  kRobokassaAuthHost,
  '/Merchant/Index/',
);

/// Checkout page used when paying with a previously saved card (`Token`).
final Uri kSavedCardPaymentUrl = Uri.https(
  kRobokassaAuthHost,
  '/Merchant/Payment/CoFPayment',
);

/// Extended payment-state web service. Returns XML.
final Uri kOperationStateUrl = Uri.https(
  kRobokassaAuthHost,
  '/Merchant/WebService/Service.asmx/OpStateExt',
);

/// Legacy payment-state web service. Returns XML.
final Uri kOperationStateLegacyUrl = Uri.https(
  kRobokassaAuthHost,
  '/Merchant/WebService/Service.asmx/OpState',
);

/// Confirms (captures) a two-stage payment previously placed on hold.
final Uri kHoldConfirmUrl = Uri.https(
  kRobokassaAuthHost,
  '/Merchant/Payment/Confirm',
);

/// Cancels (releases) a two-stage payment previously placed on hold.
final Uri kHoldCancelUrl = Uri.https(
  kRobokassaAuthHost,
  '/Merchant/Payment/Cancel',
);

/// Charges a recurring payment against a previous invoice.
final Uri kRecurringUrl = Uri.https(kRobokassaAuthHost, '/Merchant/Recurring');

/// Prefix of the URL the checkout WebView lands on once the payment reaches a
/// terminal state. Both native SDKs treat this as the "flow finished, start
/// polling the state service" trigger.
const String kPaymentStateRedirectPrefix =
    'https://auth.robokassa.ru/Merchant/State/';
