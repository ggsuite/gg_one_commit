// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one_state/gg_one_state.dart';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:matcher/expect.dart';
import 'package:mocktail/mocktail.dart';
import 'package:gg_one_checks/gg_one_checks.dart';

/// Are the last changes ready for »git commit«?
class CanCommit extends CommandCluster {
  /// Constructor
  CanCommit({
    required super.ggLog,
    Checks? checks,
    super.name = 'commit',
    super.description = 'Check if this repo can be committed',
    super.shortDescription = 'Can commit?',
    super.stateKey = 'canCommit',
  }) : super(commands: _checks(checks, ggLog));

  // ...........................................................................
  static List<DirCommand<void>> _checks(Checks? checks, GgLog ggLog) {
    checks ??= Checks(ggLog: ggLog);

    return [
      checks.pubGetOffline,
      checks.analyze,
      checks.format,
      // Bridge repos are built before their tests run, because their Dart side
      // and their tests consume the compiled TypeScript output (dist/). A
      // no-op for every other project type.
      checks.build,
      checks.tests,
      checks.packageJsonScripts,
    ];
  }
}

// .............................................................................
/// A mocktail mock
class MockCanCommit extends MockDirCommand<void> implements CanCommit {
  /// Makes [exec] successful or not
  @override
  void mockExec({
    required void result,
    Directory? directory,
    GgLog? ggLog,
    bool? force,
    bool? saveState,
    bool doThrow = false,
    String? message,
  }) {
    when(
      () => exec(
        directory: any(
          named: 'directory',
          that: predicate<Directory>(
            (d) => directory == null || d.path == directory.path,
          ),
        ),
        ggLog: ggLog ?? any(named: 'ggLog'),
        force: force,
        saveState: saveState,
      ),
    ).thenAnswer((invocation) async {
      return defaultReaction(
        doThrow: doThrow,
        invocation: invocation,
        result: null,
        message: message,
      );
    });
  }

  // ...........................................................................
  /// Mocks the result of the get command
  @override
  void mockGet({
    required void result,
    Directory? directory,
    GgLog? ggLog,
    bool? force,
    bool? saveState,
    bool doThrow = false,
    String? message,
  }) {
    when(
      () => get(
        ggLog: ggLog ?? any(named: 'ggLog'),
        directory: any(
          named: 'directory',
          that: predicate<Directory>(
            (d) => directory == null || d.path == directory.path,
          ),
        ),
        saveState: saveState,
        force: force,
      ),
    ).thenAnswer((invocation) async {
      return defaultReaction(
        doThrow: doThrow,
        invocation: invocation,
        result: null,
        message: message,
      );
    });
  }
}
