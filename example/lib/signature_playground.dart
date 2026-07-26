import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:robokassa_sdk/robokassa_sdk.dart';

/// Shows the pure-Dart half of the SDK: signed links, the exact pre-image that
/// gets hashed, and callback verification.
///
/// Everything here runs without the native SDKs, so it also works on desktop
/// and in tests.
class SignaturePlayground extends StatefulWidget {
  /// Creates the playground.
  const SignaturePlayground({required this.robokassa, super.key});

  /// SDK instance bound to the credentials entered on the first screen.
  final Robokassa robokassa;

  @override
  State<SignaturePlayground> createState() => _SignaturePlaygroundState();
}

class _SignaturePlaygroundState extends State<SignaturePlayground> {
  final _invoiceId = TextEditingController(text: '1042');
  final _amount = TextEditingController(text: '149.90');
  final _callback = TextEditingController(
    text: 'OutSum=149.90&InvId=1042&SignatureValue=paste_the_one_you_received',
  );

  bool _attachReceipt = false;
  ReceiptSignatureMode _receiptMode = ReceiptSignatureMode.urlEncoded;

  @override
  void dispose() {
    _invoiceId.dispose();
    _amount.dispose();
    _callback.dispose();
    super.dispose();
  }

  PaymentParams get _params {
    final sum = double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 1;
    return PaymentParams(
      order: OrderParams(
        invoiceId: int.tryParse(_invoiceId.text.trim()),
        orderSum: sum,
        description: 'Playground order',
        receipt: _attachReceipt
            ? Receipt(
                items: <ReceiptItem>[
                  ReceiptItem(
                    name: 'Example item',
                    sum: sum,
                    quantity: 1,
                    tax: Tax.none,
                  ),
                ],
              )
            : null,
      ),
      customer: const CustomerParams(culture: Culture.ru),
    );
  }

  @override
  Widget build(BuildContext context) {
    final builder = RobokassaLinkBuilder(
      credentials: widget.robokassa.credentials,
      receiptMode: _receiptMode,
    );

    String link;
    String base;
    String digest;
    try {
      final params = _params;
      link = builder.buildUri(params).toString();
      // The pre-image embeds password #1 — shown here only because this is a
      // developer playground running against a test shop.
      base = builder.signatureFor(params).base;
      digest = builder.signatureFor(params).value;
    } on ArgumentError catch (error) {
      link = base = digest = 'Invalid: ${error.message}';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _invoiceId,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'InvId (blank = Robokassa assigns)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'OutSum',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        SwitchListTile(
          value: _attachReceipt,
          onChanged: (value) => setState(() => _attachReceipt = value),
          title: const Text('Attach a fiscal receipt'),
          contentPadding: EdgeInsets.zero,
        ),
        if (_attachReceipt)
          SegmentedButton<ReceiptSignatureMode>(
            segments: const <ButtonSegment<ReceiptSignatureMode>>[
              ButtonSegment<ReceiptSignatureMode>(
                value: ReceiptSignatureMode.urlEncoded,
                label: Text('URL-encoded'),
              ),
              ButtonSegment<ReceiptSignatureMode>(
                value: ReceiptSignatureMode.rawJson,
                label: Text('Raw JSON'),
              ),
            ],
            selected: <ReceiptSignatureMode>{_receiptMode},
            onSelectionChanged: (selection) =>
                setState(() => _receiptMode = selection.first),
          ),
        const SizedBox(height: 16),
        _CopyableCard(
          title: 'Signature pre-image (contains password #1)',
          value: base,
        ),
        _CopyableCard(
          title:
              'SignatureValue (${widget.robokassa.credentials.algorithm.name})',
          value: digest,
        ),
        _CopyableCard(title: 'Payment link', value: link),
        const Divider(height: 32),
        Text(
          'Verify a callback',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _callback,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'ResultURL query string or form body',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        _CallbackResult(robokassa: widget.robokassa, body: _callback.text),
      ],
    );
  }
}

class _CallbackResult extends StatelessWidget {
  const _CallbackResult({required this.robokassa, required this.body});

  final Robokassa robokassa;
  final String body;

  @override
  Widget build(BuildContext context) {
    final RobokassaCallback callback;
    try {
      callback = RobokassaCallback.parseFormBody(
        body,
        kind: RobokassaCallbackKind.result,
        credentials: robokassa.credentials,
      );
    } on StateError catch (error) {
      return _CopyableCard(title: 'Cannot verify', value: error.message);
    } on FormatException catch (error) {
      return _CopyableCard(title: 'Cannot parse', value: '$error');
    }

    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: callback.isConfirmedPayment
          ? scheme.primaryContainer
          : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              callback.isConfirmedPayment
                  ? 'Signature valid — reply "${callback.acknowledgement}"'
                  : 'NOT a confirmed payment',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SelectableText(
              callback.signatureError ?? callback.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyableCard extends StatelessWidget {
  const _CopyableCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Copied')));
                  }
                },
              ),
            ],
          ),
          SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
