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

/// Upgrades all dependencies of the package — **every ecosystem it has**.
///
/// - a `pubspec.yaml` is upgraded with »dart pub upgrade [--major-versions]
///   --tighten« (»flutter pub upgrade …« in a Flutter repo)
/// - a `package.json` is upgraded with the project's package manager
///   (»pnpm update [--latest]«, »yarn upgrade [--latest]«, »npm update«)
///
/// The two are independent, so a *hybrid* — a repository carrying both
/// manifests — runs both. Before, the command returned early without a
/// `pubspec.yaml`, so a TypeScript repository was never upgraded at all and a
/// hybrid only ever saw its Dart side move.
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

    // Each manifest is looked at on its own, so a hybrid upgrades both sides.
    final hasPubspec = File('${directory.path}/pubspec.yaml').existsSync();
    final hasPackageJson = File('${directory.path}/package.json').existsSync();

    if (!hasPubspec && !hasPackageJson) {
      ggLog(
        cDetail(
          'No pubspec.yaml and no package.json — nothing '
          'to upgrade.',
        ),
      );
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
    //
    // Dart goes first: its »pub upgrade --tighten« rewrites pubspec.lock, and
    // a hybrid's npm lifecycle scripts may shell into the Dart side, which
    // should then already be resolved.
    if (hasPubspec) {
      await _runDartPubUpgrade(
        directory: directory,
        majorVersions: majorVersions,
      );
    }

    if (hasPackageJson) {
      await _runNodeUpgrade(directory: directory, majorVersions: majorVersions);
    }

    // Tell the user whether the upgrade changed anything. The verdict covers
    // both ecosystems, because the hash covers both lock files.
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
  /// Runs the node package manager's upgrade — »pnpm update [--latest]« and
  /// its yarn/npm equivalents.
  ///
  /// `pnpm-workspace.yaml` is restored afterwards when the run rewrote it. In
  /// a ticket workspace its `overrides` section redirects siblings to
  /// `link:../…` (written by `gg_localize_refs`), and pnpm is known to rewrite
  /// such specs to `file:` — which copies instead of symlinking, so edits in a
  /// sibling would silently stop propagating mid-ticket.
  Future<void> _runNodeUpgrade({
    required Directory directory,
    required bool majorVersions,
  }) async {
    final packageManager = detectTypeScriptPackageManager(directory);

    final workspaceFile = File('${directory.path}/$_pnpmWorkspaceFileName');
    final workspaceBefore = workspaceFile.existsSync()
        ? workspaceFile.readAsStringSync()
        : null;

    await _runNodeCommand(
      directory: directory,
      command: packageManager.updateCommand(latest: majorVersions),
    );

    // The generic upgrade above crosses every major boundary. Bring the
    // packages gg holds at a fixed version back down — this also repairs a
    // repository that already drifted past the pin. Runs regardless of
    // --major-versions: the pin states which version the repository must be
    // on, it is not an upgrade policy.
    final declared = readNpmDependencyNames(directory);
    for (final entry in pinnedNpmVersions.entries) {
      // Pinning a package the repository never declared would add it.
      if (!declared.contains(entry.key)) {
        continue;
      }
      await _runNodeCommand(
        directory: directory,
        command: packageManager.pinCommand(
          package: entry.key,
          version: entry.value,
        ),
      );
    }

    if (workspaceBefore != null &&
        workspaceFile.readAsStringSync() != workspaceBefore) {
      workspaceFile.writeAsStringSync(workspaceBefore);
      ggLog(
        cWarn(
          'The upgrade rewrote $_pnpmWorkspaceFileName — restored it so the '
          'local sibling references stay intact.',
        ),
      );
    }
  }

  // ...........................................................................
  /// Runs one node package-manager command and reports it like every other
  /// step of the upgrade.
  Future<void> _runNodeCommand({
    required Directory directory,
    required ({String executable, List<String> args}) command,
  }) async {
    final label = '${command.executable} ${command.args.join(' ')}';

    await GgStatusPrinter<bool>(
      message: 'Run »$label«',
      ggLog: ggLog,
      dark: true,
    ).logTask(
      task: () async {
        final result = await _processWrapper.run(
          command.executable,
          command.args,
          workingDirectory: directory.path,
          // npm/pnpm/yarn are shell shims (pnpm.cmd on Windows, a PATH script
          // elsewhere), so run through a shell — otherwise Windows cannot
          // find the executable.
          runInShell: true,
          // pnpm 11 blocks »exotic« sub-dependencies (git refs) by default,
          // which a ticket workspace legitimately carries.
          environment: const <String, String>{
            'PNPM_CONFIG_BLOCK_EXOTIC_SUBDEPS': 'false',
          },
        );

        if (result.exitCode != 0) {
          throw Exception(cError('»$label« failed: ${result.stderr}'));
        }

        return true;
      },
      success: (success) => success,
    );
  }

  /// pnpm's per-repository settings file, which also carries the `link:`
  /// overrides `gg_localize_refs` writes.
  static const String _pnpmWorkspaceFileName = 'pnpm-workspace.yaml';

  // ...........................................................................
  /// Runs »dart pub upgrade« — »flutter pub upgrade« in a Flutter repo, where
  /// plain `dart pub` cannot resolve the `sdk: flutter` dependencies.
  Future<void> _runDartPubUpgrade({
    required Directory directory,
    required bool majorVersions,
  }) async {
    // detectProjectType, not checkProjectType: the latter reports *any*
    // hybrid as typescript, so a hybrid Flutter repository would silently get
    // »dart pub upgrade« and fail to resolve its »sdk: flutter« dependencies.
    final executable = detectProjectType(directory) == ProjectType.flutter
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
