// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one_core/gg_one_core.dart';
import 'dart:convert';
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
    final manifestFile = File('${directory.path}/package.json');
    final manifestBefore = manifestFile.readAsStringSync();

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

    _restoreLocalizedSpecs(file: manifestFile, before: manifestBefore);

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
  /// Puts back every dependency spec the node upgrade turned into a *local*
  /// one (`link:`, `file:`, `workspace:`).
  ///
  /// In a ticket workspace `pnpm-workspace.yaml` redirects the siblings to
  /// their checkouts, and pnpm writes the spec it *resolved* back into
  /// `package.json` — so an upgrade silently replaces a published constraint
  /// like `^1.0.1` with `link:../../ggsuite/base_dna`. That is a path nobody
  /// outside this workspace can resolve: `gg can merge` refuses to merge it,
  /// and publishing it would ship a broken manifest.
  ///
  /// The published constraints belong in `package.json`, the redirection in
  /// `pnpm-workspace.yaml` — this keeps that split intact. Specs that were
  /// already local before the upgrade are left alone; undoing a deliberate
  /// state is not this method's job.
  void _restoreLocalizedSpecs({required File file, required String before}) {
    final Map<String, String> restore;
    try {
      restore = _specsToRestore(before: before, after: file.readAsStringSync());
      // coverage:ignore-start
    } catch (_) {
      return; // An unparsable manifest is reported by the checks that own it.
    }
    // coverage:ignore-end

    if (restore.isEmpty) {
      return;
    }

    // Edited textually so the formatting of the file survives.
    var content = file.readAsStringSync();
    restore.forEach((name, spec) {
      final key = RegExp.escape(name);
      content = content.replaceAllMapped(
        RegExp(
          '("$key"'
          r'\s*:\s*)'
          '"[^"]*"',
        ),
        (match) => '${match[1]}"$spec"',
      );
    });
    file.writeAsStringSync(content);

    ggLog(
      cWarn(
        'The upgrade replaced the published constraint of '
        '${restore.keys.join(', ')} with a local reference — restored it. '
        'The redirection belongs in $_pnpmWorkspaceFileName.',
      ),
    );
  }

  // ...........................................................................
  /// Dependency name → spec it carried before, for every dependency that is
  /// local *after* the upgrade but was not before.
  static Map<String, String> _specsToRestore({
    required String before,
    required String after,
  }) {
    final result = <String, String>{};
    final oldJson = jsonDecode(before);
    final newJson = jsonDecode(after);
    if (oldJson is! Map<String, dynamic> || newJson is! Map<String, dynamic>) {
      return result; // coverage:ignore-line
    }

    for (final section in const <String>[
      'dependencies',
      'devDependencies',
      'peerDependencies',
      'optionalDependencies',
    ]) {
      final oldEntries = oldJson[section];
      final newEntries = newJson[section];
      if (oldEntries is! Map || newEntries is! Map) continue;
      newEntries.forEach((key, value) {
        final name = key.toString();
        final oldValue = oldEntries[name];
        if (value is! String || oldValue is! String) return;
        if (_isLocalSpec(value) && !_isLocalSpec(oldValue)) {
          result[name] = oldValue;
        }
      });
    }
    return result;
  }

  // ...........................................................................
  /// Whether [spec] points at a checkout instead of a registry release.
  static bool _isLocalSpec(String spec) =>
      spec.startsWith('link:') ||
      spec.startsWith('file:') ||
      spec.startsWith('workspace:');

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
