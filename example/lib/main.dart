import 'package:flutter/material.dart';
import 'package:robokassa_sdk/robokassa_sdk.dart';

import 'credentials_screen.dart';
import 'payments_screen.dart';
import 'signature_playground.dart';

void main() => runApp(const RobokassaExampleApp());

/// Demonstrates every payment mode the Robokassa SDK supports.
///
/// Credentials are entered at runtime rather than hard-coded: passwords
/// committed to a repository have a way of reaching production builds.
class RobokassaExampleApp extends StatefulWidget {
  /// Creates the example app.
  const RobokassaExampleApp({super.key});

  @override
  State<RobokassaExampleApp> createState() => _RobokassaExampleAppState();
}

class _RobokassaExampleAppState extends State<RobokassaExampleApp> {
  ShopConfig? _config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Robokassa SDK example',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF00A0E3),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF00A0E3),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: _config == null
          ? CredentialsScreen(
              onSubmit: (config) => setState(() => _config = config),
            )
          : _HomeScreen(
              config: _config!,
              onSignOut: () => setState(() => _config = null),
            ),
    );
  }
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen({required this.config, required this.onSignOut});

  final ShopConfig config;
  final VoidCallback onSignOut;

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  late Robokassa _robokassa = Robokassa(credentials: widget.config.credentials);
  int _tab = 0;

  @override
  void didUpdateWidget(_HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.credentials != widget.config.credentials) {
      _robokassa.dispose();
      _robokassa = Robokassa(credentials: widget.config.credentials);
    }
  }

  @override
  void dispose() {
    _robokassa.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTest = widget.config.credentials.isTest;
    return Scaffold(
      appBar: AppBar(
        title: Text(isTest ? 'Robokassa — test mode' : 'Robokassa — LIVE'),
        backgroundColor: isTest
            ? null
            : Theme.of(context).colorScheme.errorContainer,
        actions: <Widget>[
          IconButton(
            tooltip: 'Change credentials',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: <Widget>[
          PaymentsScreen(
            robokassa: _robokassa,
            redirectUrl: widget.config.redirectUrl,
          ),
          SignaturePlayground(robokassa: _robokassa),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.payment_outlined),
            selectedIcon: Icon(Icons.payment),
            label: 'Native checkout',
          ),
          NavigationDestination(
            icon: Icon(Icons.link_outlined),
            selectedIcon: Icon(Icons.link),
            label: 'Links & signatures',
          ),
        ],
      ),
    );
  }
}
