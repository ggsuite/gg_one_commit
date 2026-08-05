// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:gg_one_core/gg_one_core.dart';

void main() {
  late Directory d;
  final messages = <String>[];
  // Strip the colors so the expectations stay readable. One closure
  // instance, not a function declaration: mocktail matches the ggLog
  // argument by identity, and a tear-off is not stable.
  // ignore: prefer_function_declarations_over_variables
  final GgLog ggLog = (String msg) => messages.add(rmControls(msg));
  late CommandRunner<void> runner;
  late DoUpgradeDeps doUpgrade;

  // ...........................................................................
  late GgState? state;
  late MockCanUpgrade canUpgrade;
  late MockGgProcessWrapper processWrapper;

  // ...........................................................................
  void initMocks() {
    registerFallbackValue(d);
    registerFallbackValue(<String>[]);
    state = GgState(ggLog: ggLog);
    canUpgrade = MockCanUpgrade();
    processWrapper = MockGgProcessWrapper();
  }

  // ...........................................................................
  void initDoUpgrade() {
    doUpgrade = DoUpgradeDeps(
      ggLog: ggLog,
      state: state,
      canUpgrade: canUpgrade,
      processWrapper: processWrapper,
    );

    runner.addCommand(doUpgrade);
  }

  // ...........................................................................
  void mockDartPubUpgrade({
    bool majorVersions = true,
    int exitCode = 0,
    String stdout = '',
    String stderr = '',
    bool upgradingCausesChange = true,
    String executable = 'dart',
  }) {
    when(
      () => processWrapper.run(executable, [
        'pub',
        'upgrade',
        if (majorVersions) '--major-versions',
        '--tighten',
      ], workingDirectory: d.path),
    ).thenAnswer((_) async {
      if (upgradingCausesChange) {
        await updateSampleFileWithoutCommitting(d);
      }

      return ProcessResult(0, exitCode, stdout, stderr);
    });
  }

  // ...........................................................................
  void initDefaultMocks() {
    canUpgrade.mockExec(result: null, directory: d, ggLog: ggLog);
    mockDartPubUpgrade();
  }

  // ...........................................................................
  setUp(() async {
    d = await Directory.systemTemp.createTemp();
    await initGit(d);
    await addAndCommitSampleFile(d);
    await addAndCommitPubspecFile(d);

    messages.clear();
    runner = CommandRunner<void>('gg', 'gg');
    initMocks();
    initDoUpgrade();
    initDefaultMocks();
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  // ...........................................................................
  group('DoUpgradeDeps', () {
    group('- main case', () {
      group('- should run »dart pub upggrade», '
          'check if everything still runs (canCommit) '
          'and finally commit and publish changes', () {
        void check() {
          expect(messages[0], contains('✓ CanUpgrade'));
          expect(
            messages[1],
            contains('⌛️ Run »dart pub upgrade --major-versions --tighten«'),
          );
          expect(
            messages[2],
            contains('✓ Run »dart pub upgrade --major-versions --tighten«'),
          );
        }

        test('- programmatically', () async {
          await doUpgrade.exec(directory: d, ggLog: ggLog);
          check();
        });

        test('- via CLI', () async {
          await runner.run(['deps', '-i', d.path]);
          check();
        });
      });
    });

    group('- edge cases', () {
      group('- should fail', () {
        group('- when preconditions for can upgrade are not met', () {
          setUp(() {
            // Let canUpgrade fail
            canUpgrade.mockExec(
              result: null,
              directory: d,
              doThrow: true, // <- Throws
              message: 'CanUpgrade failed',
            );
          });

          Future<void> perform(Future<void> testCode) async {
            late String exception;
            try {
              await testCode;
            } catch (e) {
              exception = rmControls(e.toString());
            }
            expect(exception, contains('CanUpgrade failed'));
          }

          test('- programmatically', () async {
            await perform(doUpgrade.exec(directory: d, ggLog: ggLog));
          });

          test('- via CLI', () async {
            await perform(runner.run(['deps', d.path, '-i', d.path]));
          });
        });

        test('- when »dart pub upgrade« exists with an error', () async {
          mockDartPubUpgrade(exitCode: 1, stderr: 'Something went wrong');

          late String exception;
          try {
            await doUpgrade.exec(directory: d, ggLog: ggLog);
          } catch (e) {
            exception = rmControls(e.toString());
          }
          expect(
            exception,
            contains('»dart pub upgrade« failed: Something went wrong'),
          );
        });
      });

      group('- should do nothing', () {
        group('- when »dart pub upgrade« changes nothing', () {
          setUp(() {
            mockDartPubUpgrade(upgradingCausesChange: false);
          });

          void check() {
            expect(messages.last, 'Everything is already up to date.');
          }

          test('- programmatically', () async {
            await doUpgrade.exec(directory: d, ggLog: ggLog);
            check();
          });

          test('- via CLI', () async {
            await runner.run(['deps', d.path, '-i', d.path]);
            check();
          });
        });

        group('- when there is no pubspec.yaml', () {
          test('- programmatically', () async {
            File('${d.path}/pubspec.yaml').deleteSync();
            await doUpgrade.exec(directory: d, ggLog: ggLog);
            expect(messages.last, 'No pubspec.yaml — nothing to upgrade.');
            verifyNever(
              () => processWrapper.run(
                any(),
                any(),
                workingDirectory: any(named: 'workingDirectory'),
              ),
            );
          });
        });
      });

      group('- should not commit and publish ', () {
        test('when nothing was changed by »dart pub upgrade«', () async {
          mockDartPubUpgrade(upgradingCausesChange: false);
          await doUpgrade.exec(directory: d, ggLog: ggLog);
          final allMessages = messages.join('\n');
          expect(allMessages, isNot(contains('✓ DoCommit')));
          expect(allMessages, isNot(contains('✓ DoPublish')));
        });
      });

      group('- should allow to skip major versions', () {
        setUp(() {
          mockDartPubUpgrade(majorVersions: false);
        });

        tearDown(() {
          expect(messages[1], contains('⌛️ Run »dart pub upgrade --tighten«'));

          expect(messages[2], contains('✓ Run »dart pub upgrade --tighten«'));
        });

        test('- programmatically', () async {
          await doUpgrade.exec(
            directory: d,
            ggLog: ggLog,
            majorVersions: false,
          );
        });

        test('- via CLI', () async {
          await runner.run(['deps', '-i', d.path, '--no-major-versions']);
        });
      });

      group('- should use flutter for Flutter repos', () {
        setUp(() {
          // A top-level `flutter:` key makes checkProjectType report the
          // repo as a Flutter package.
          File(
            '${d.path}/pubspec.yaml',
          ).writeAsStringSync('name: test\nflutter:\n  uses-material: true\n');
          mockDartPubUpgrade(executable: 'flutter');
        });

        tearDown(() {
          expect(
            messages[1],
            contains('⌛️ Run »flutter pub upgrade --major-versions --tighten«'),
          );
          expect(
            messages[2],
            contains('✓ Run »flutter pub upgrade --major-versions --tighten«'),
          );
        });

        test('- programmatically', () async {
          await doUpgrade.exec(directory: d, ggLog: ggLog);
        });

        test('- via CLI', () async {
          await runner.run(['deps', '-i', d.path]);
        });
      });

      test('- should init DoUpgradeDeps with default params', () {
        expect(() => DoUpgradeDeps(ggLog: ggLog), returnsNormally);
      });
    });
  });

  // #########################################################################
  group('MockDoUpgradeDeps', () {
    group('mockExec', () {
      group('should mock exec', () {
        test('with ggLog', () async {
          final didUpgrade = MockDoUpgradeDeps();
          didUpgrade.mockExec(
            result: null,
            directory: d,
            ggLog: ggLog,
            majorVersions: true,
          );

          await didUpgrade.exec(
            directory: d,
            ggLog: ggLog,
            majorVersions: true,
          );

          expect(messages[0], contains('✓ DoUpgradeDeps'));
        });

        test('without ggLog', () async {
          final didUpgrade = MockDoUpgradeDeps();
          didUpgrade.mockExec(
            result: null,
            directory: d,
            majorVersions: true,
            ggLog: null, // <-- ggLog is null
          );

          await didUpgrade.exec(
            directory: d,
            majorVersions: true,
            ggLog: (_) {},
          );

          expect(messages, isEmpty);
        });
      });
    });

    group('mockGet', () {
      group('should mock get', () {
        test('with ggLog', () async {
          final didUpgrade = MockDoUpgradeDeps();
          didUpgrade.mockGet(
            result: null,
            directory: d,
            ggLog: ggLog,
            majorVersions: true,
          );

          await didUpgrade.get(directory: d, ggLog: ggLog, majorVersions: true);

          expect(messages[0], contains('✓ DoUpgradeDeps'));
        });

        test('without ggLog', () async {
          final didUpgrade = MockDoUpgradeDeps();
          didUpgrade.mockGet(
            result: null,
            directory: d,
            majorVersions: true,
            ggLog: null, // <-- ggLog is null
          );

          await didUpgrade.get(
            directory: d,
            majorVersions: true,
            ggLog: (_) {},
          );

          expect(messages, isEmpty);
        });
      });
    });
  });
}
