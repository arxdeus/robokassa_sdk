import 'package:flutter/material.dart';
import 'package:robokassa_sdk/robokassa_sdk.dart';

/// Shop settings the example needs: credentials plus the success-redirect URL,
/// which lives on [PaymentParams] rather than on [RobokassaCredentials].
typedef ShopConfig = ({RobokassaCredentials credentials, String? redirectUrl});

/// Collects the shop credentials the rest of the example runs on.
class CredentialsScreen extends StatefulWidget {
  /// Creates the credentials form.
  const CredentialsScreen({required this.onSubmit, super.key});

  /// Called once the form holds a usable configuration.
  final ValueChanged<ShopConfig> onSubmit;

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password1 = TextEditingController();
  final _password2 = TextEditingController();
  final _redirectUrl = TextEditingController();

  HashAlgorithm _algorithm = HashAlgorithm.md5;
  bool _isTest = true;

  @override
  void dispose() {
    _login.dispose();
    _password1.dispose();
    _password2.dispose();
    _redirectUrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final redirectUrl = _redirectUrl.text.trim();
    widget.onSubmit((
      credentials: RobokassaCredentials(
        merchantLogin: _login.text.trim(),
        password1: _password1.text,
        password2: _password2.text,
        algorithm: _algorithm,
        isTest: _isTest,
      ),
      redirectUrl: redirectUrl.isEmpty ? null : redirectUrl,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Robokassa credentials')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'In test mode Robokassa validates against the TEST password '
                  'pair, so enter those here when the switch below is on.\n\n'
                  'A production app should not carry password #2 at all — see '
                  'the package README on why, and prefer creating payments on '
                  'your own server.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _login,
              decoration: const InputDecoration(
                labelText: 'MerchantLogin',
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password1,
              decoration: const InputDecoration(
                labelText: 'Password #1',
                helperText: 'Signs outgoing requests',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password2,
              decoration: const InputDecoration(
                labelText: 'Password #2',
                helperText: 'Required by the native SDKs to poll payment state',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _redirectUrl,
              decoration: const InputDecoration(
                labelText: 'Success redirect URL (optional)',
                helperText: 'Android watches for this to detect completion',
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<HashAlgorithm>(
              initialValue: _algorithm,
              decoration: const InputDecoration(
                labelText: 'Hash algorithm',
                helperText: 'Must match Технические настройки for the shop',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<HashAlgorithm>>[
                for (final algorithm in HashAlgorithm.values)
                  DropdownMenuItem<HashAlgorithm>(
                    value: algorithm,
                    child: Text(algorithm.name.toUpperCase()),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _algorithm = value ?? HashAlgorithm.md5),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _isTest,
              onChanged: (value) => setState(() => _isTest = value),
              title: const Text('Test mode (IsTest=1)'),
              subtitle: Text(
                _isTest
                    ? 'No real money moves.'
                    : 'REAL money will move. Use with care.',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.login),
              label: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
