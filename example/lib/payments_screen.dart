import 'package:flutter/material.dart';
import 'package:robokassa_sdk/robokassa_sdk.dart';

/// Runs every native checkout mode against a live (or test) Robokassa shop.
class PaymentsScreen extends StatefulWidget {
  /// Creates the payments screen.
  const PaymentsScreen({required this.robokassa, this.redirectUrl, super.key});

  /// SDK instance bound to the credentials entered on the previous screen.
  final Robokassa robokassa;

  /// Success-redirect URL configured for the shop, if any.
  final String? redirectUrl;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final _invoiceId = TextEditingController(
    // A per-run starting point keeps repeated test payments from colliding on
    // InvId, which Robokassa rejects as a duplicate.
    text: (DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000000)
        .toString(),
  );
  final _amount = TextEditingController(text: '10.00');
  final _email = TextEditingController(text: 'buyer@example.com');

  bool _busy = false;
  bool _attachReceipt = true;
  String _log = 'Ready.';

  /// Remembered from the last successful payment so the saved-card and
  /// recurring flows have something to work with.
  String? _lastOpKey;
  int? _lastPaidInvoiceId;
  int? _lastHeldInvoiceId;

  @override
  void dispose() {
    _invoiceId.dispose();
    _amount.dispose();
    _email.dispose();
    super.dispose();
  }

  int get _invoice => int.tryParse(_invoiceId.text.trim()) ?? 0;
  double get _sum =>
      double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0;

  PaymentParams _params({
    bool isHold = false,
    bool isRecurrent = false,
    String? token,
    int? previousInvoiceId,
    int? invoiceIdOverride,
    double? sumOverride,
  }) {
    final sum = sumOverride ?? _sum;
    return PaymentParams(
      order: OrderParams(
        invoiceId: invoiceIdOverride ?? _invoice,
        orderSum: sum,
        description: 'robokassa_sdk example order',
        isHold: isHold,
        isRecurrent: isRecurrent,
        token: token,
        previousInvoiceId: previousInvoiceId,
        expirationDate: DateTime.now().add(const Duration(days: 1)),
        receipt: _attachReceipt
            ? Receipt(
                items: <ReceiptItem>[
                  ReceiptItem(
                    name: 'Example item',
                    sum: sum,
                    quantity: 1,
                    paymentMethod: PaymentMethod.fullPayment,
                    paymentObject: PaymentObject.commodity,
                    tax: Tax.none,
                  ),
                ],
              )
            : null,
      ),
      customer: CustomerParams(
        culture: Culture.ru,
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      ),
      view: const ViewParams(
        toolbarText: 'Оплата заказа',
        toolbarBgColor: '#00A0E3',
        toolbarTextColor: '#FFFFFF',
      ),
      // Echoed back on every callback and folded into the signature.
      userParameters: UserParameters(<String, Object?>{
        'source': 'flutter_example',
      }),
      redirectUrl: widget.redirectUrl,
    );
  }

  Future<void> _run(String label, Future<Object?> Function() action) async {
    setState(() {
      _busy = true;
      _log = '$label…';
    });
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        if (result is RobokassaPaymentResult) {
          _log = '$label\n\n${result.diagnostics}';
          if (result.isSuccess) {
            _lastOpKey = result.opKey ?? _lastOpKey;
            if (result.isHeld) {
              _lastHeldInvoiceId = result.invoiceId ?? _invoice;
            } else {
              _lastPaidInvoiceId = result.invoiceId ?? _invoice;
            }
          }
        } else {
          _log = '$label\n\n$result';
        }
      });
    } on RobokassaNativeException catch (error) {
      if (mounted) setState(() => _log = '$label failed\n\n$error');
    } on RobokassaApiException catch (error) {
      if (mounted) setState(() => _log = '$label failed\n\n$error');
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _log = '$label rejected\n\n${error.message}');
    } on StateError catch (error) {
      if (mounted) setState(() => _log = '$label rejected\n\n${error.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Bumps the invoice number so the next test payment is unique.
  void _nextInvoice() =>
      setState(() => _invoiceId.text = (_invoice + 1).toString());

  @override
  Widget build(BuildContext context) {
    final robokassa = widget.robokassa;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _invoiceId,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'InvId',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Next invoice number',
              onPressed: _nextInvoice,
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'OutSum',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Customer email',
            border: OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          value: _attachReceipt,
          onChanged: (value) => setState(() => _attachReceipt = value),
          title: const Text('Attach a fiscal receipt'),
          subtitle: const Text('Participates in SignatureValue'),
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(height: 24),

        _Section('Checkout flows (open the native 3-D Secure screen)'),
        _Action(
          label: 'Simple payment',
          icon: Icons.credit_card,
          enabled: !_busy,
          onPressed: () =>
              _run('Simple payment', () => robokassa.pay(_params())),
        ),
        _Action(
          label: 'Two-stage payment (hold funds)',
          icon: Icons.pause_circle_outline,
          enabled: !_busy,
          onPressed: () =>
              _run('Hold', () => robokassa.payWithHold(_params(isHold: true))),
        ),
        _Action(
          label: 'First payment of a recurring series',
          icon: Icons.repeat,
          enabled: !_busy,
          onPressed: () => _run(
            'Recurring — first payment',
            () => robokassa.payRecurrentFirst(_params(isRecurrent: true)),
          ),
        ),
        _Action(
          label: 'Pay with the saved card',
          icon: Icons.bookmark_outline,
          subtitle: _lastOpKey == null
              ? 'Needs an opKey — run a simple payment first'
              : 'Using opKey ${_lastOpKey!.substring(0, 8)}…',
          enabled: !_busy && _lastOpKey != null,
          onPressed: () => _run(
            'Saved-card payment',
            () => robokassa.payWithSavedCard(
              _params(token: _lastOpKey, invoiceIdOverride: _invoice + 1),
            ),
          ),
        ),

        const Divider(height: 24),
        _Section('Headless operations (no UI)'),
        _Action(
          label: 'Capture the held payment',
          icon: Icons.check_circle_outline,
          subtitle: _lastHeldInvoiceId == null
              ? 'Needs a held payment first'
              : 'Invoice $_lastHeldInvoiceId',
          enabled: !_busy && _lastHeldInvoiceId != null,
          onPressed: () => _run(
            'Confirm hold',
            () async =>
                await robokassa.confirmHold(
                  _params(isHold: true, invoiceIdOverride: _lastHeldInvoiceId),
                )
                ? 'Captured.'
                : 'Robokassa refused the capture.',
          ),
        ),
        _Action(
          label: 'Release the held payment',
          icon: Icons.cancel_outlined,
          subtitle: _lastHeldInvoiceId == null
              ? 'Needs a held payment first'
              : 'Invoice $_lastHeldInvoiceId',
          enabled: !_busy && _lastHeldInvoiceId != null,
          onPressed: () => _run(
            'Cancel hold',
            () async =>
                await robokassa.cancelHold(
                  _params(isHold: true, invoiceIdOverride: _lastHeldInvoiceId),
                )
                ? 'Released.'
                : 'Robokassa refused the release.',
          ),
        ),
        _Action(
          label: 'Charge the next recurring payment',
          icon: Icons.autorenew,
          subtitle: _lastPaidInvoiceId == null
              ? 'Needs a paid recurring parent first'
              : 'Parent invoice $_lastPaidInvoiceId',
          enabled: !_busy && _lastPaidInvoiceId != null,
          onPressed: () => _run(
            'Recurring charge',
            () async =>
                await robokassa.chargeRecurring(
                  _params(
                    invoiceIdOverride: _invoice + 1,
                    previousInvoiceId: _lastPaidInvoiceId,
                  ),
                )
                ? 'Charge accepted — confirm via ResultURL.'
                : 'Robokassa refused the charge.',
          ),
        ),
        _Action(
          label: 'Query payment state',
          icon: Icons.help_outline,
          subtitle: 'Native on Android, Dart HTTP on iOS',
          enabled: !_busy,
          onPressed: () => _run(
            'Payment state',
            () => robokassa.checkPaymentState(_params()),
          ),
        ),
        _Action(
          label: 'Full state detail (pure Dart)',
          icon: Icons.receipt_long_outlined,
          subtitle:
              'RobokassaApi.getPaymentState — amounts, method, timestamps',
          enabled: !_busy,
          onPressed: () =>
              _run('OpStateExt', () => robokassa.api.getPaymentState(_invoice)),
        ),
        _Action(
          label: 'Check the native SDK is linked',
          icon: Icons.link,
          enabled: !_busy,
          onPressed: () => _run(
            'Native SDK availability',
            () async => await robokassa.isNativeSdkAvailable()
                ? 'The native Robokassa SDK is linked into this build.'
                : 'NOT linked — see the README installation section.',
          ),
        ),

        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text(
                      'Result',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (_busy)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _log,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.subtitle,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      enabled: enabled,
      onTap: enabled ? onPressed : null,
      leading: Icon(icon),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
      tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
