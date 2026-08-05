// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_git/gg_git.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:gg_one_core/gg_one_core.dart';

// .............................................................................
void main() {
  late Directory d;
  late Checks commands;
  final messages = <String>[];

  // Strip the colors so the expectations stay readable. One closure
  // instance, not a function declaration: mocktail matches the ggLog
  // argument by identity, and a tear-off is not stable.
  // ignore: prefer_function_declarations_over_variables
  final GgLog ggLog = (String msg) => messages.add(rmControls(msg));
  late CanPush push;

  // ...........................................................................
  void mockCommands() {
    when(
      () => commands.isCommitted.exec(directory: d, ggLog: ggLog),
    ).thenAnswer((_) async {
      messages.add('did commit');
      return true;
    });
  }

  // ...........................................................................
  setUp(() async {
    commands = Checks(
      ggLog: ggLog,
      isCommitted: MockIsCommitted(),
      isUpgraded: MockIsUpgraded(),
    );

    push = CanPush(ggLog: ggLog, checkCommands: commands);
    d = Directory.systemTemp.createTempSync();
    await initGit(d);
    mockCommands();
  });

  // ...........................................................................
  tearDown(() {
    d.deleteSync(recursive: true);
  });

  // ...........................................................................
  group('Can', () {
    group('Push', () {
      group('constructor', () {
        test('with defaults', () {
          final c = CanPush(ggLog: ggLog);
          expect(c.name, 'push');
          expect(c.description, 'Check if this repo can be pushed');
        });
      });
      group('run(directory)', () {
        test('should check if everything is upgraded and commited', () async {
          await addAndCommitSampleFile(d);
          await push.exec(directory: d, ggLog: ggLog);
          expect(messages[0], 'did commit');
        });
      });
    });
  });
}
