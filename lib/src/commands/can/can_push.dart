// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one_state/gg_one_state.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one_commit/src/commands/can/can_commit.dart';
import 'package:gg_one_checks/gg_one_checks.dart';

/// Are the last changes ready for »git push«?
class CanPush extends CommandCluster {
  /// Constructor
  CanPush({
    required super.ggLog,
    Checks? checkCommands,
    super.name = 'push',
    super.shortDescription = 'Can push?',
    super.description = 'Check if this repo can be pushed',
    super.stateKey = 'canPush',
  }) : super(commands: _checks(checkCommands, ggLog));

  // ...........................................................................
  /// `pubGetOffline` runs first, exactly as in [CanCommit]: the lock file is
  /// tracked, so a background `pub get` — the Dart VS Code extension fires one
  /// whenever a manifest is written — leaves it modified and `isCommitted`
  /// would refuse a push over a file nobody edited. Syncing it with the
  /// manifest first turns that noise into a deterministic state.
  static List<DirCommand<void>> _checks(Checks? checks, GgLog ggLog) {
    checks ??= Checks(ggLog: ggLog);
    return [checks.pubGetOffline, checks.isCommitted];
  }
}

// .............................................................................
/// A mocktail mock
class MockCanPush extends MockDirCommand<void> implements CanPush {}
