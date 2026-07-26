#!/usr/bin/env dart

// Fetches Robokassa's native SDKs into an app's project so the plugin can
// compile against them.
//
// Run from the folder that contains `android/` and `ios/`:
//
//     dart run robokassa_sdk:fetch_native_sdks
//
// This exists because Robokassa ships its mobile SDKs as GitHub source rather
// than as published artifacts, so every consuming app has to vendor them. See
// the "Installation" section of the robokassa_sdk README.
library;

import 'dart:io';

/// Upstream repositories, pinned to a tag where one exists.
const _repositories = <({String name, String url, String? tag})>[
  (
    name: 'sdk-android',
    url: 'https://github.com/robokassa/sdk-android.git',
    tag: null,
  ),
  (
    name: 'sdk-ios',
    url: 'https://github.com/robokassa/sdk-ios.git',
    tag: '1.0.0',
  ),
];

Future<int> main(List<String> arguments) async {
  final target = Directory(arguments.isNotEmpty ? arguments.first : 'native');

  if (!Directory('android').existsSync() && !Directory('ios').existsSync()) {
    stderr.writeln(
      'Neither ./android nor ./ios exists here.\n'
      'Run this from your Flutter app folder (the one holding android/ and '
      'ios/), or pass an explicit destination:\n'
      '    dart run robokassa_sdk:fetch_native_sdks <destination>',
    );
    return 2;
  }

  if (!await _hasGit()) {
    stderr.writeln('git was not found on PATH; install it and try again.');
    return 2;
  }

  target.createSync(recursive: true);
  stdout.writeln('Fetching Robokassa native SDKs into ${target.path}/');

  for (final repository in _repositories) {
    final destination = Directory('${target.path}/${repository.name}');
    if (destination.existsSync()) {
      stdout.writeln('  ${repository.name}: already present, skipping');
      continue;
    }

    final args = <String>[
      'clone',
      '--depth',
      '1',
      if (repository.tag != null) ...<String>['--branch', repository.tag!],
      repository.url,
      destination.path,
    ];
    stdout.writeln('  ${repository.name}: cloning…');
    final result = await Process.run('git', args);
    if (result.exitCode != 0) {
      stderr
        ..writeln('  ${repository.name}: clone FAILED')
        ..writeln(result.stderr);
      return result.exitCode;
    }
  }

  stdout.writeln(
    '\nDone.\n\n'
    'Android — add this to android/settings.gradle.kts (once):\n'
    '    val robokassaLibrary = file("../${target.path}/sdk-android/Robokassa_Library")\n'
    '    if (robokassaLibrary.isDirectory) {\n'
    '        include(":Robokassa_Library")\n'
    '        project(":Robokassa_Library").projectDir = robokassaLibrary\n'
    '    }\n\n'
    'iOS — add this to ios/Podfile inside your Runner target (once):\n'
    "    pod 'RobokassaSDK', :git => 'https://github.com/robokassa/sdk-ios.git', :tag => '1.0.0'\n\n"
    'Then run `flutter clean && flutter pub get` (and `pod install` for iOS).',
  );
  return 0;
}

Future<bool> _hasGit() async {
  try {
    final result = await Process.run('git', <String>['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
