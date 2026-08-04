// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one_state/gg_one_state.dart';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one_commit/src/commands/can/can_push.dart';
import 'package:gg_process/gg_process.dart';

/// Pushes the current state.
class DoPush extends DirCommand<void> {
  /// Constructor
  DoPush({
    required super.ggLog,
    super.name = 'push',
    super.description = 'Push changes in this repo',
    IsPushed? isPushed,
    CanPush? canPush,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    GgState? state,
    UpstreamBranch? upstreamBranch,
    LocalBranch? localBranch,
  }) : _processWrapper = processWrapper,
       _isPushedViaGit = isPushed ?? IsPushed(ggLog: ggLog),
       _canPush = canPush ?? CanPush(ggLog: ggLog),
       _upstreamBranch = upstreamBranch ?? UpstreamBranch(ggLog: ggLog),
       _localBranch = localBranch ?? LocalBranch(ggLog: ggLog),
       state = state ?? GgState(ggLog: ggLog) {
    _addParam();
  }

  // ...........................................................................
  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? force,
  }) => get(directory: directory, ggLog: ggLog, force: force);

  // ...........................................................................
  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? force,
  }) async {
    // Does directory exist?
    await check(directory: directory);

    // Is everything pushed?
    final isPushedViaGit = await _isPushedViaGit.get(
      directory: directory,
      ggLog: (_) {}, // coverage:ignore-line
    );

    // Is didPush already set?
    if (isPushedViaGit) {
      final isDone = await state.readSuccess(
        directory: directory,
        key: stateKey,
        ggLog: ggLog,
      );

      if (isDone) {
        ggLog(cDetail('Already checked and pushed.'));
        return;
      }
    }

    // Is everything fine?
    await _canPush.exec(directory: directory, ggLog: ggLog);

    // Write success before pushing
    await state.writeSuccess(directory: directory, key: stateKey);

    // Did .gg.json change? Is a new push needed?
    final isPushedViaGitAfterWritingSuccess = await _isPushedViaGit.get(
      directory: directory,
      ggLog: ggLog,
    );

    // Execute the commit
    if (!isPushedViaGitAfterWritingSuccess) {
      force ??= _forceFromArgs();
      await gitPush(directory: directory, force: force);
      ggLog(cDetail('Checks successful. Pushed successful.'));
    }
  }

  /// The state used to save the state of the command
  final GgState state;

  /// The key used to save the state of the command
  final String stateKey = 'doPush';

  // ######################
  // Private
  // ######################

  // ...........................................................................
  final GgProcessWrapper _processWrapper;
  final IsPushed _isPushedViaGit;
  final CanPush _canPush;

  final UpstreamBranch _upstreamBranch;
  final LocalBranch _localBranch;

  // ...........................................................................
  void _addParam() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Do a force push.',
      defaultsTo: false,
      negatable: true,
    );
  }

  // ...........................................................................
  /// Pushes the current state to the remote.
  Future<void> gitPush({
    required Directory directory,
    required bool force,
    bool pushTags = false,
  }) async {
    final didPush = await _pushNewBranch(directory);
    if (!didPush) {
      await _pushExistingBranch(force, pushTags, directory);
    }
  }

  // ...........................................................................
  Future<void> _pushExistingBranch(
    bool force,
    bool pushTags,
    Directory directory,
  ) async {
    final result = await _processWrapper.run('git', [
      'push',
      if (force) '-f',
      if (pushTags) '--tags', // coverage:ignore-line
    ], workingDirectory: directory.path);

    if (result.exitCode != 0) {
      throw Exception(cError('git push failed: ${result.stderr}'));
    }
  }

  // ...........................................................................
  Future<bool> _pushNewBranch(Directory directory) async {
    final upstreamBranch = await _upstreamBranch.get(
      ggLog: ggLog,
      directory: directory,
    );

    if (upstreamBranch.isNotEmpty) {
      return false;
    }

    final localBranch = await _localBranch.get(
      ggLog: ggLog,
      directory: directory,
    );

    final result = await _processWrapper.run('git', [
      'push',
      '--set-upstream',
      'origin',
      localBranch,
    ], workingDirectory: directory.path);

    if (result.exitCode != 0) {
      throw Exception(
        cError(
          'git push --set-upstream origin $localBranch failed: '
          '${result.stderr}',
        ),
      );
    }

    return true;
  }

  // ...........................................................................
  bool _forceFromArgs() {
    final force = argResults?['force'] as bool? ?? false;
    return force;
  }
}

/// Mock for [DoPush].
class MockDoPush extends MockDirCommand<void> implements DoPush {}
