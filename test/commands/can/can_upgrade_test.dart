// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  late CanUpgrade canUpgrade;
  late CommandRunner<void> runner;

  final messages = <String>[];
  // Strip the colors so the expectations stay readable. One closure
  // instance, not a function declaration: mocktail matches the ggLog
  // argument by identity, and a tear-off is not stable.
  // ignore: prefer_function_declarations_over_variables
  final GgLog ggLog = (String msg) => messages.add(rmControls(msg));

  // ...........................................................................
  setUp(() async {
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    await initGit(d);
    await addAndCommitSampleFile(d);
    registerFallbackValue(d);
    canUpgrade = CanUpgrade(ggLog: ggLog);
    runner = CommandRunner<void>('test', 'test')..addCommand(canUpgrade);
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  // ...........................................................................
  group('CanUpgrade', () {
    group('should succeed', () {
      tearDown(() {});

      test('programmatically', () async {
        await canUpgrade.exec(directory: d, ggLog: ggLog);
      });

      test('via CLI', () async {
        await runner.run(['upgrade', d.path]);
      });
    });

    group('edge cases', () {
      test('initialized with default arguments', () {
        final canUpgrade = CanUpgrade(ggLog: ggLog);
        expect(canUpgrade.name, 'upgrade');
        expect(canUpgrade.description, 'Check if this repo can be upgraded');
      });
    });
  });
}
