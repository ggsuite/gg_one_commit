// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one_core/gg_one_core.dart';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_lang/gg_lang.dart';
import 'package:gg_one_commit/src/commands/can/can_upgrade.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:matcher/expect.dart';
import 'package:mocktail/mocktail.dart';

/// Upgrades all dependencies of the package via
/// »dart pub upgrade [--major-versions] --tighten«
/// (»flutter pub upgrade …« in a Flutter repo).
///
/// The upgrade itself runs no checks — the flows that call it (`gg do push`,
/// `gg do publish`) run `gg can commit` right afterwards, so validating here
/// would only duplicate that step.
class DoUpgradeDeps extends DirCommand<void> {
  /// Constructor
  DoUpgradeDeps({
    required super.ggLog,
    super.name = 'deps',
    super.description = 'Upgrade all dependencies of this repo',
    GgState? state,
    CanUpgrade? canUpgrade,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
  }) : _state = state ?? GgState(ggLog: ggLog),
       _processWrapper = processWrapper,
       _canUpgrade = canUpgrade ?? CanUpgrade(ggLog: ggLog) {
    _addParam();
  }

  // ...........................................................................
  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? majorVersions,
    Map<String, dynamic> options = const {},
  }) => get(directory: directory, ggLog: ggLog, majorVersions: majorVersions);

  // ...........................................................................
  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? majorVersions,
  }) async {
    majorVersions ??= _majorVersionsFromArgs;

    // Does directory exist?
    await check(directory: directory);

    // Without a pubspec.yaml there are no pub dependencies to upgrade.
    // The ticket-wide caller also visits TypeScript repos, where
    // »dart pub upgrade« would fail.
    final pubspec = File('${directory.path}/pubspec.yaml');
    if (!pubspec.existsSync()) {
      ggLog(cDetail('No pubspec.yaml — nothing to upgrade.'));
      return;
    }

    // Can upgrade?
    await _canUpgrade.exec(directory: directory, ggLog: ggLog);

    // Remember the state before the upgrade
    final hashBefore = await _state.currentHash(
      directory: directory,
      ggLog: ggLog,
    );

    // Perform the upgrade. Runs unconditionally: a versions-only check would
    // skip »--tighten« exactly when the bounds are loose but the versions are
    // current.
    await _runDartPubUpgrade(
      directory: directory,
      majorVersions: majorVersions,
    );

    // Tell the user whether the upgrade changed anything.
    final hashAfter = await _state.currentHash(
      directory: directory,
      ggLog: ggLog,
    );

    if (hashBefore == hashAfter) {
      ggLog(cDetail('Everything is already up to date.'));
    }
  }

  /// The key used to save the state of the command
  final String stateKey = 'doUpgrade';

  // ######################
  // Private
  // ######################

  // ...........................................................................
  final GgState _state;
  final GgProcessWrapper _processWrapper;
  final CanUpgrade _canUpgrade;

  // ...........................................................................
  void _addParam() {
    argParser.addFlag(
      'major-versions',
      abbr: 'm',
      help: 'Upgrade packages to their latest versions',
      defaultsTo: true,
      negatable: true,
    );
  }

  // ...........................................................................
  /// Runs »dart pub upgrade« — »flutter pub upgrade« in a Flutter repo, where
  /// plain `dart pub` cannot resolve the `sdk: flutter` dependencies.
  Future<void> _runDartPubUpgrade({
    required Directory directory,
    required bool majorVersions,
  }) async {
    final executable = checkProjectType(directory) == ProjectType.flutter
        ? 'flutter'
        : 'dart';

    final args = [
      'pub',
      'upgrade',
      if (majorVersions) '--major-versions',
      '--tighten',
    ];

    await GgStatusPrinter<bool>(
      message: 'Run »$executable ${args.join(' ')}«',
      ggLog: ggLog,
      dark: true,
    ).logTask(
      task: () async {
        final result = await _processWrapper.run(
          executable,
          args,
          workingDirectory: directory.path,
        );

        if (result.exitCode != 0) {
          throw Exception(
            cError('»$executable pub upgrade« failed: ${result.stderr}'),
          );
        }

        return true;
      },
      success: (success) => success,
    );
  }

  // ...........................................................................
  bool get _majorVersionsFromArgs {
    final majorVersions = argResults?['major-versions'] as bool? ?? true;
    return majorVersions;
  }
}

/// Mock for [DoUpgradeDeps].
class MockDoUpgradeDeps extends MockDirCommand<void> implements DoUpgradeDeps {
  // ...........................................................................
  /// Makes [exec] successful or not
  @override
  void mockExec({
    void result,
    GgLog? ggLog,
    Directory? directory,
    bool? majorVersions,
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
        majorVersions: majorVersions,
      ),
    ).thenAnswer((invocation) async {
      return defaultReaction(
        doThrow: doThrow,
        message: message,
        invocation: invocation,
        result: null,
      );
    });
  }

  // ...........................................................................
  /// Makes [get] successful or not
  @override
  void mockGet({
    void result,
    GgLog? ggLog,
    Directory? directory,
    bool? majorVersions,
    bool doThrow = false,
    String? message,
  }) {
    when(
      () => get(
        directory: any(
          named: 'directory',
          that: predicate<Directory>(
            (d) => directory == null || d.path == directory.path,
          ),
        ),
        ggLog: ggLog ?? any(named: 'ggLog'),
        majorVersions: majorVersions,
      ),
    ).thenAnswer((invocation) async {
      return defaultReaction(
        doThrow: doThrow,
        message: message,
        invocation: invocation,
        result: null,
      );
    });
  }
}
