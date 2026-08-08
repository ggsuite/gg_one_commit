// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one_core/gg_one_core.dart';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_changelog/gg_changelog.dart' as cl;
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_lang/gg_lang.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one_commit/src/commands/can/can_commit.dart';
import 'package:gg_one_commit/src/tools/ocean_folder_guard.dart';
import 'package:gg_one_commit/src/tools/repository_url.dart';
import 'package:gg_process/gg_process.dart';

cl.LogType _stringToLogType(String e) {
  e = e.toLowerCase();

  if (e.startsWith('add')) {
    return cl.LogType.added;
  } else if (e.contains('change')) {
    return cl.LogType.changed;
  } else if (e.contains('deprecate')) {
    return cl.LogType.deprecated;
  } else if (e.contains('fix')) {
    return cl.LogType.fixed;
  } else if (e.contains('remove')) {
    return cl.LogType.removed;
  } else if (e.contains('secure')) {
    return cl.LogType.security;
  }

  return cl.LogType.changed;
}

// .............................................................................
/// Does a commit of the current directory.
class DoCommit extends DirCommand<void> {
  /// Constructor
  DoCommit({
    required super.ggLog,
    super.name = 'commit',
    super.description = 'Commit changes in this repo',
    IsCommitted? isCommitted,
    CanCommit? canCommit,
    Commit? commit,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    GgState? state,
    cl.Add? addToChangeLog,
    IsFeatureBranch? isFeatureBranch,
    LocalBranch? localBranch,
  }) : _processWrapper = processWrapper,
       _isFeatureBranch = isFeatureBranch ?? IsFeatureBranch(ggLog: ggLog),
       _localBranch = localBranch ?? LocalBranch(ggLog: ggLog),
       _isGitCommitted = isCommitted ?? IsCommitted(ggLog: ggLog),
       _canCommit = canCommit ?? CanCommit(ggLog: ggLog),
       _commit = commit ?? Commit(ggLog: ggLog),
       state = state ?? GgState(ggLog: ggLog),
       _addToChangeLog = addToChangeLog ?? cl.Add(ggLog: ggLog) {
    _addParam();
  }

  // ...........................................................................
  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    String? message,
    cl.LogType? logType,
    bool? updateChangeLog,
    bool? force,
    Map<String, dynamic> options = const {},
  }) => get(
    directory: directory,
    ggLog: ggLog,
    message: message,
    logType: logType,
    updateChangeLog: updateChangeLog,
    force: force,
  );

  // ...........................................................................
  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    String? message,
    cl.LogType? logType,
    bool? updateChangeLog,
    bool? force,
  }) async {
    // Read flags
    force ??= _forceFromArgs();

    // Does directory exist?
    await check(directory: directory);

    // Commits do not belong into the ocean. --force bypasses the
    // guard, so an ocean repo can still be fixed in place.
    if (force != true) {
      throwWhenInOceanFolder(directory);
    }

    // Commits must never be created on the default branch. --force bypasses
    // the guard, so a main branch can still be fixed in place.
    if (force != true) {
      await _checkIsFeatureBranch(directory: directory);
    }

    // Is everything committed?
    final isCommittedViaGit = await _isGitCommitted.get(
      directory: directory,
      ggLog: ggLog,
    );

    // Is didCommit already set?
    if (isCommittedViaGit) {
      final isDone = await state.readSuccess(
        directory: directory,
        key: stateKey,
        ggLog: ggLog,
      );

      if (isDone) {
        ggLog(cDetail('✓ Committed'));
        return;
      }
    }

    // Check needed options
    try {
      message ??= _getMessageFromArgs();
      logType ??= _getLogTypeFromMessage(message);
    } catch (e) {
      // type and message are only needed when there are uncommitted changes.
      if (!isCommittedViaGit) {
        rethrow;
      } else {
        logType = cl.LogType.changed;
        message = '';
      }
    }

    // CHANGELOG update currently depends on cider, which requires
    // pubspec.yaml. Skip it for TypeScript projects until we have a
    // TypeScript-native changelog writer.
    // Bridges are treated as TypeScript (no Dart CHANGELOG/cider step).
    final supportsChangeLog = checkProjectType(directory).isDartFamily;

    final repoUrl = supportsChangeLog ? await readRepositoryUrl(directory) : '';

    // Is everything fine? Skip checks when --force is used
    if (force != true) {
      await _canCommit.exec(directory: directory, ggLog: ggLog);
    }

    // Update changelog when a message is given
    updateChangeLog ??= argResults?['log'] as bool? ?? true;
    if (updateChangeLog && supportsChangeLog) {
      await _writeMessageIntoChangeLog(
        directory: directory,
        message: message,
        logType: logType,
        repoUrl: repoUrl,
        commit: isCommittedViaGit,
      );
    }

    // Execute the commit
    if (!isCommittedViaGit) {
      await gitAddAndCommit(
        directory: directory,
        message: message,
        logType: logType,
      );
    }

    // Save the state
    await state.writeSuccess(directory: directory, key: stateKey);
  }

  /// The state used to save the state of the command
  final GgState state;

  /// The key used to save the state of the command
  final String stateKey = 'doCommit';

  // ...........................................................................
  /// Adds and commits the current directory.
  Future<void> gitAddAndCommit({
    required Directory directory,
    required String message,
    required cl.LogType logType,
  }) async {
    await _gitAdd(directory, message);
    await _gitCommit(directory: directory, message: message, logType: logType);
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................
  final GgProcessWrapper _processWrapper;
  final IsFeatureBranch _isFeatureBranch;
  final LocalBranch _localBranch;
  final IsCommitted _isGitCommitted;
  final CanCommit _canCommit;
  final Commit _commit;
  final cl.Add _addToChangeLog;

  // ...........................................................................
  void _addParam() {
    argParser.addFlag(
      'log',
      abbr: 'l',
      help: 'Do not add message to CHANGELOG.md.',
      negatable: true,
      defaultsTo: true,
    );

    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'The commit message and log entry.',
    );

    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Commit without running checks (analyze/format/tests).',
      defaultsTo: false,
      negatable: true,
    );
  }

  // ...........................................................................
  /// Throws when the current branch is »main« or »master«.
  ///
  /// Callers skip the guard when »--force« is given — the message names that
  /// escape hatch.
  Future<void> _checkIsFeatureBranch({required Directory directory}) async {
    final isFeatureBranch = await _isFeatureBranch.get(
      directory: directory,
      ggLog: (_) {}, // coverage:ignore-line
    );

    if (isFeatureBranch) {
      return;
    }

    final branch = await _localBranch.get(directory: directory, ggLog: (_) {});

    final where = branch.isEmpty ? 'a detached HEAD' : 'branch »$branch«';

    throw Exception(
      cError(
        'Cannot commit on $where.\n'
        'Switch to a feature branch, e.g. '
        '${cCmd('gg do checkout <ticket>')}'
        '\nOr commit anyway using '
        '${cCmd('gg do commit --force')}',
      ),
    );
  }

  // ...........................................................................
  Future<void> _gitAdd(Directory directory, String message) async {
    final result = await _processWrapper.run('git', [
      'add',
      '.',
    ], workingDirectory: directory.path);

    if (result.exitCode != 0) {
      throw Exception(cError('git add failed: ${result.stderr}'));
    }
  }

  // ...........................................................................
  /// Executes the git commit command.
  Future<void> _gitCommit({
    required Directory directory,
    required String message,
    required cl.LogType logType,
  }) async {
    final result = await _processWrapper.run('git', [
      'commit',
      '-m',
      message,
    ], workingDirectory: directory.path);

    if (result.exitCode != 0) {
      throw Exception(cError('git commit failed: ${result.stderr}'));
    }
  }

  // ...........................................................................
  /// The help text printed when message is missing.
  String get helpOnMissingMessage {
    final part0 = cAction('Run again with message.\n');
    final part1 = cCmd('gg do commit ${green('-m<your message>')}');
    return '$part0$part1';
  }

  // ...........................................................................
  cl.LogType _getLogTypeFromMessage(String message) {
    try {
      return _stringToLogType(message);
    } catch (e) {
      return cl.LogType.changed;
    }
  }

  // ...........................................................................
  String _getMessageFromArgs() {
    final String message = (argResults?['message'] ?? '') as String;
    if (message.isEmpty) {
      throw Exception(cError(helpOnMissingMessage));
    }

    return message;
  }

  // ...........................................................................
  Future<bool> _writeMessageIntoChangeLog({
    required Directory directory,
    required String message,
    required cl.LogType logType,
    required String repoUrl,
    required bool commit,
  }) async {
    // Check if message is already in CHANGELOG.md
    final changeLog = await File(
      '${directory.path}/CHANGELOG.md',
    ).readAsString();

    if (changeLog.contains(message)) {
      return false;
    }

    // Remember hash before
    final hashBefore = await state.currentHash(
      directory: directory,
      ggLog: ggLog,
    );

    // Use cider to write into CHANGELOG.md
    await _addToChangeLog.exec(
      directory: directory,
      ggLog: (_) {}, // coverage:ignore-line
      message: message,
      logType: logType,
    );

    // Replace previous hash by new hash in .gg.json
    // Thus »gg can commit|push|publish« will not start from beginning
    await state.updateHash(hash: hashBefore, directory: directory);

    // If everything was committed before, commit the new changes also
    if (commit) {
      await _commit.commit(
        ggLog: (_) {}, // coverage:ignore-line
        directory: directory,
        doStage: true,
        message: message,
        ammendWhenNotPushed: true,
      );
    }

    return true;
  }

  // ...........................................................................
  bool _forceFromArgs() {
    return argResults?['force'] as bool? ?? false;
  }
}

// .............................................................................
/// Mock for [DoCommit].
class MockDoCommit extends MockDirCommand<void> implements DoCommit {}
