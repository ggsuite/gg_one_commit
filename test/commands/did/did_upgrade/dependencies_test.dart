// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  late MockIsUpgraded isUpgraded;
  late DidUpgradeDependencies didUpgrade;
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
    registerFallbackValue(d);
    isUpgraded = MockIsUpgraded();
    didUpgrade = DidUpgradeDependencies(ggLog: ggLog, isUpgraded: isUpgraded);
    runner = CommandRunner<void>('test', 'test')..addCommand(didUpgrade);
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  // ...........................................................................
  group('DidUpgradeDependencies', () {
    group('should check', () {
      group('if everything is upgraded', () {
        for (final viaCli in [true, false]) {
          test('via CLI and programmatically', () async {
            isUpgraded.mockGet(result: true);

            if (viaCli == false) {
              await didUpgrade.exec(directory: d, ggLog: ggLog);
            } else {
              await runner.run(['dependencies', '-i', d.path]);
            }
            expect(messages[0], contains('⌛️ Everything is upgraded'));
            expect(messages[1], contains('✓ Everything is upgraded'));
          });
        }
      });
    });

    group('should handle edge cases: ', () {
      test('instantiate without optional parameters', () {
        expect(() => DidUpgradeDependencies(ggLog: ggLog), returnsNormally);
      });
    });
  });

  // #########################################################################
  group('MockDidUpgradeDependencies', () {
    group('mockGet', () {
      group('should mock get', () {
        test('with ggLog', () async {
          final didUpgrade = MockDidUpgradeDependencies();
          didUpgrade.mockGet(
            result: true,
            directory: d,
            ggLog: ggLog,
            majorVersions: true,
          );

          final result = await didUpgrade.get(
            directory: d,
            ggLog: ggLog,
            majorVersions: true,
          );

          expect(result, isTrue);
          expect(messages[0], contains('✓ DidUpgradeDependencies'));
        });

        test('without ggLog', () async {
          final didUpgrade = MockDidUpgradeDependencies();
          didUpgrade.mockGet(
            result: true,
            directory: d,
            majorVersions: true,
            ggLog: null, // <-- ggLog is null
          );

          final result = await didUpgrade.get(
            directory: d,
            majorVersions: true,
            ggLog: (_) {},
          );

          expect(result, isTrue);
          expect(messages, isEmpty);
        });
      });
    });
  });
}
