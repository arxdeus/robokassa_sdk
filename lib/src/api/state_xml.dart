import 'package:xml/xml.dart';

import '../core/amount.dart';
import '../models/payment_state.dart';

/// Parses the XML returned by `OpState` / `OpStateExt` into a [PaymentState].
///
/// Robokassa serves these documents in the
/// `http://merchant.roboxchange.com/WebService/` namespace, so every lookup
/// here matches on **local** element names and ignores the namespace — the
/// same tolerance the official SDKs' `konsumeXml` traversal has.
///
/// Throws [FormatException] when [xml] is not well-formed or is not an
/// `OperationStateResponse`.
PaymentState parseOperationStateXml(String xml) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException catch (error) {
    throw FormatException(
      'Robokassa returned a malformed state document: ${error.message}',
      xml,
    );
  }

  final root = _firstLocal(document, 'OperationStateResponse');
  if (root == null) {
    // Robokassa answers a rejected request with a bare <string> fault or an
    // HTML error page; surfacing the body beats a null-pointer downstream.
    throw FormatException(
      'Expected an <OperationStateResponse> document from the Robokassa state '
      'service.',
      xml,
    );
  }

  final result = _childLocal(root, 'Result');
  final state = _childLocal(root, 'State');
  final info = _childLocal(root, 'Info');

  final resultCode = RequestResultCode.tryParse(_text(result, 'Code'));
  final stateCode = PaymentStateCode.tryParse(_text(state, 'Code'));

  final paymentMethod = info == null
      ? null
      : _childLocal(info, 'PaymentMethod');

  return PaymentState(
    // An unparseable <Result><Code> means we cannot trust the answer at all,
    // so fall back to `checking` rather than inventing a success.
    requestResult: resultCode ?? RequestResultCode.checking,
    stateCode: stateCode ?? PaymentStateCode.notInitialized,
    description: _text(result, 'Description'),
    opKey: _text(info, 'OpKey'),
    stateDate: _parseDate(
      _text(state, 'StateDate') ?? _text(state, 'RequestDate'),
    ),
    incCurrLabel: _text(info, 'IncCurrLabel'),
    incSum: parseOutSum(_text(info, 'IncSum')),
    incAccount: _text(info, 'IncAccount'),
    paymentMethodCode: _text(paymentMethod, 'Code'),
    outCurrLabel: _text(info, 'OutCurrLabel'),
    outSum: parseOutSum(_text(info, 'OutSum')),
    rawXml: xml,
  );
}

XmlElement? _firstLocal(XmlDocument document, String localName) {
  for (final element in document.descendantElements) {
    if (element.name.local == localName) return element;
  }
  return null;
}

XmlElement? _childLocal(XmlElement? parent, String localName) {
  if (parent == null) return null;
  for (final element in parent.childElements) {
    if (element.name.local == localName) return element;
  }
  return null;
}

String? _text(XmlElement? parent, String localName) {
  final child = _childLocal(parent, localName);
  if (child == null) return null;
  final value = child.innerText.trim();
  return value.isEmpty ? null : value;
}

DateTime? _parseDate(String? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw);
}
