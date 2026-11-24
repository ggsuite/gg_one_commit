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
    show DnaHost, IoDnaHost, dnaConfigPath, placeDnaCheck;
import 'package:path/path.dart' as p;

// #############################################################################

/// Keeps the DNA check of a repository in place, so its tests fail as soon
/// as a file the DNA generated is changed or deleted by hand.
///
/// Runs only in a repository with a DNA (`dna/_dna.json`). There it places
/// the check helix provides — `test/dna/dna_test.dart` or
/// `test/dna/dna.spec.ts` — or replaces an older one, and removes a check
/// that no longer fits. The change is committed right away as
/// [commitMessage], like every file the DNA generates, so a commit of an
/// otherwise clean repository does not leave it behind. The check needs the
/// engine and a test framework as dependencies; without them nothing is
/// placed, and a warning names the dependency to declare.
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

  /// Message of the commit that carries the placed or removed check.
  static const String commitMessage = '#gg: DNA check';

  /// Warning for a repository with a DNA but without a check: [package] is
  /// the dependency to declare.
  static String notCheckedWarning(String package) =>
      'The DNA is not checked: declare $package as dev dependency.';

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
    final changed = [...result.placed, ...result.removed];
    if (changed.isNotEmpty) {
      try {
        await _host.commitPaths(root, changed, commitMessage);
      } on Object catch (e) {
        ggLog(yellow('Could not commit the DNA check ($e) — commit it.'));
      }
    }

    final missing = result.missing;
    if (missing != null) ggLog(yellow(notCheckedWarning(missing)));
  }
}

// .............................................................................
/// A mocktail mock.
class MockEnsureDnaCheck extends MockDirCommand<void>
    implements EnsureDnaCheck {}
