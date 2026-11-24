// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:helix/helix.dart'
    show
        DnaHost,
        IoDnaHost,
        dartDnaCheckPath,
        dnaConfigPath,
        placeDnaCheck,
        tsDnaCheckPath;
import 'package:mocktail/mocktail.dart' as mocktail;
import 'package:path/path.dart' as p;

// #############################################################################

/// Keeps the DNA check of a repository in place, so its tests fail as soon
/// as a file the DNA generated is changed or deleted by hand.
///
/// Runs only in a repository with a DNA (`dna/_dna.json`). There it places
/// the check helix provides — `test/dna/dna_test.dart` or
/// `test/dna/dna.spec.ts` — or replaces an older one, and removes a check
/// that no longer fits. The check needs the engine as a dependency (`helix`,
/// or `@tssuite/helix-js`); without it, nothing is placed and a warning
/// says that the DNA is not checked.
class EnsureDnaCheck extends DirCommand<void> {
  /// Constructor.
  EnsureDnaCheck({required super.ggLog, DnaHost? host})
    : _host = host ?? IoDnaHost(),
      super(
        name: 'ensure-dna-check',
        description: 'Places the DNA check in a repository with a DNA.',
      );

  /// Example instance for tests — logs to `print`.
  factory EnsureDnaCheck.example() => EnsureDnaCheck(ggLog: print);

  final DnaHost _host;

  /// Warning for a repository with a DNA but without the engine.
  static const String noEngineWarning =
      'The DNA is not checked: declare helix (Dart) or @tssuite/helix-js '
      '(TypeScript) as dev dependency.';

  // ...........................................................................
  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    final root = directory.absolute.path.replaceAll(r'\', '/');
    if (!_host.existsFile(p.posix.join(root, dnaConfigPath))) return;

    final result = placeDnaCheck(_host, root);
    for (final path in result.placed) {
      ggLog(cDetail('✓ Placed DNA check $path'));
    }
    for (final path in result.removed) {
      ggLog(cDetail('✓ Removed DNA check $path'));
    }

    final hasCheck =
        _host.existsFile('$root/$dartDnaCheckPath') ||
        _host.existsFile('$root/$tsDnaCheckPath');
    if (!hasCheck) ggLog(yellow(noEngineWarning));
  }
}

// .............................................................................
/// A mocktail mock.
class MockEnsureDnaCheck extends mocktail.Mock implements EnsureDnaCheck {}
