// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:gg_test/gg_test.dart';
import 'package:gg_version/gg_version.dart';
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
  late CanCommit commit;

  // ...........................................................................
  void mockCommands() {
    when(() => commands.pubGetOffline.exec(directory: d, ggLog: ggLog))
        .thenAnswer((_) async {
          messages.add('did pub get');
        });
    when(() => commands.analyze.exec(directory: d, ggLog: ggLog))
        .thenAnswer((_) async {
          messages.add('did analyze');
        });
    when(() => commands.format.exec(directory: d, ggLog: ggLog))
        .thenAnswer((_) async {
          messages.add('did format');
        });
    when(() => commands.build.exec(directory: d, ggLog: ggLog))
        .thenAnswer((_) async {
          messages.add('did build');
        });
    when(() => commands.tests.exec(directory: d, ggLog: ggLog))
        .thenAnswer((_) async {
          messages.add('did cover');
        });
    when(() => commands.packageJsonScripts.exec(directory: d, ggLog: ggLog))
        .thenAnswer((_) async {});
    when(() => commands.noFutureVersions.exec(directory: d, ggLog: ggLog))
        .thenAnswer((_) async {
          messages.add('did check future versions');
          return true;
        });
  }

  // ...........................................................................
  setUp(() async {
    commands = Checks(
      ggLog: ggLog,
      pubGetOffline: MockPubGetOffline(),
      analyze: MockAnalyze(),
      build: MockBuild(),
      format: MockFormat(),
      tests: MockTests(),
      packageJsonScripts: MockCheckPackageJsonScripts(),
      noFutureVersions: MockNoFutureVersions(),
    );

    commit = CanCommit(ggLog: ggLog, checks: commands);
    d = Directory.systemTemp.createTempSync();
    await initGit(d);
    registerFallbackValue(d);
    mockCommands();
    messages.clear();
  });

  // ...........................................................................
  tearDown(() {
    d.deleteSync(recursive: true);
  });

  // ...........................................................................
  group('Can', () {
    group('constructor', () {
      test('with defaults', () {
        final c = CanCommit(ggLog: ggLog);
        expect(c.name, 'commit');
        expect(c.description, 'Check if this repo can be committed');
      });
    });

    group('Commit', () {
      group('run(directory)', () {
        test('should run pub get, analyze, format, build, coverage and the '
            'future-versions check in that order', () async {
          await addAndCommitSampleFile(d);
          await commit.exec(directory: d, ggLog: ggLog);
          expect(messages[0], 'did pub get');
          expect(messages[1], 'did analyze');
          expect(messages[2], 'did format');
          expect(messages[3], 'did build');
          expect(messages[4], 'did cover');
          expect(messages[5], 'did check future versions');
        });
      });
    });
  });

  group('MockCanCommit', () {
    group('mockExec', () {
      group('should mock exec', () {
        Future<void> runTest({required bool useGgLog}) async {
          final canCommit = MockCanCommit();
          canCommit.mockExec(
            result: null,
            directory: d, // <-- ggLog
            ggLog: useGgLog ? ggLog : null,
            force: true,
            saveState: false,
          );

          await canCommit.exec(
            directory: d,
            ggLog: ggLog,
            force: true,
            saveState: false,
          );
          expect(messages[0], contains('✓ CanCommit'));
        }

        test('with ggLog', () async {
          await runTest(useGgLog: true);
        });

        test('with directory == null', () async {
          await runTest(useGgLog: false);
        });
      });
    });

    group('mockGet', () {
      group('should mock get', () {
        Future<void> runTest({required bool useGgLog}) async {
          final canCommit = MockCanCommit();
          canCommit.mockGet(
            result: null,
            directory: d,
            ggLog: useGgLog ? ggLog : null, // <-- ggLog
            force: true,
            saveState: false,
          );

          await canCommit.get(
            directory: d,
            ggLog: ggLog,
            force: true,
            saveState: false,
          );
          expect(messages[0], contains('✓ CanCommit'));
        }

        test('with ggLog', () async {
          await runTest(useGgLog: true);
        });

        test('with directory == null', () async {
          await runTest(useGgLog: false);
        });
      });
    });
  });
}
