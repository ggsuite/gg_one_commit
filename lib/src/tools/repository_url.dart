// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_lang/gg_lang.dart';

// #############################################################################

/// Reads the canonical repository URL of the project at [directory].
///
/// - Dart / Flutter: `repository:` in `pubspec.yaml`.
/// - TypeScript: `repository` in `package.json` (either the shorthand string
///   form or the `{ "type": "git", "url": "..." }` object form).
///
/// The returned URL is normalized: `git+` prefix and trailing `.git` or `/`
/// are stripped so the value is usable as a browsable web URL.
///
/// Throws an [Exception] if no repository URL can be found.
Future<String> readRepositoryUrl(Directory directory) async {
  final type = detectProjectType(directory);
  return switch (type) {
    ProjectType.dart || ProjectType.flutter => _readFromPubspec(directory),
    ProjectType.typescript => _readFromPackageJson(directory),
    ProjectType.none => throw Exception(
      cError('No repository URL: the project has no manifest.'),
    ),
  };
}

// .............................................................................
Future<String> _readFromPubspec(Directory directory) async {
  final pubspec = await File('${directory.path}/pubspec.yaml').readAsString();
  final match = RegExp(
    r'^\s*repository:\s*(.+)$',
    multiLine: true,
  ).firstMatch(pubspec);
  final url = match?.group(1);
  if (url == null) {
    throw Exception(cError('No »repository:« found in pubspec.yaml'));
  }
  return _normalize(url);
}

// .............................................................................
Future<String> _readFromPackageJson(Directory directory) async {
  final raw = await File('${directory.path}/package.json').readAsString();
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw Exception(cError('package.json is not a JSON object.'));
  }

  final repository = decoded['repository'];
  final url = switch (repository) {
    String s => s,
    Map<String, dynamic> m when m['url'] is String => m['url'] as String,
    _ => null,
  };

  if (url == null || url.isEmpty) {
    throw Exception(cError('No »repository« URL found in package.json'));
  }
  return _normalize(url);
}

// .............................................................................
String _normalize(String raw) {
  var url = raw.trim();
  if (url.startsWith('git+')) {
    url = url.substring(4);
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.endsWith('.git')) {
    url = url.substring(0, url.length - 4);
  }
  return url;
}
