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
  /// Turns the repo into one with a node side. [lockFile] selects the package
  /// manager (null ⇒ npm).
  void writePackageJson({
    String? lockFile = 'pnpm-lock.yaml',
    Map<String, String> devDependencies = const {},
  }) {
    final deps = devDependencies.entries
        .map((e) => '"${e.key}": "${e.value}"')
        .join(', ');
    File('${d.path}/package.json').writeAsStringSync(
      '{"name": "@org/test", "version": "1.0.0", '
      '"devDependencies": {$deps}}',
    );
    if (lockFile != null) {
      File('${d.path}/$lockFile').writeAsStringSync('');
    }
  }

  // ...........................................................................
  void mockNodeUpgrade({
    bool majorVersions = true,
    String executable = 'pnpm',
    List<String>? args,
    int exitCode = 0,
    String stderr = '',
    void Function()? onRun,
  }) {
    when(
      () => processWrapper.run(
        executable,
        args ?? ['update', if (majorVersions) '--latest'],
        workingDirectory: d.path,
        runInShell: true,
        environment: any(named: 'environment'),
      ),
    ).thenAnswer((_) async {
      onRun?.call();
      return ProcessResult(0, exitCode, '', stderr);
    });
  }

  // ...........................................................................
  void mockPin({
    String executable = 'pnpm',
    List<String>? args,
    int exitCode = 0,
    String stderr = '',
  }) {
    when(
      () => processWrapper.run(
        executable,
        args ?? ['update', '--save-exact', 'typescript@6'],
        workingDirectory: d.path,
        runInShell: true,
        environment: any(named: 'environment'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, exitCode, '', stderr));
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

        group('- when there is no manifest at all', () {
          test('- programmatically', () async {
            File('${d.path}/pubspec.yaml').deleteSync();
            await doUpgrade.exec(directory: d, ggLog: ggLog);
            expect(
              messages.last,
              'No pubspec.yaml and no package.json — nothing to upgrade.',
            );
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

      // .....................................................................
      group('- the node side', () {
        test('is upgraded for a pure TypeScript repo', () async {
          // Before, such a repo returned early and was never upgraded.
          File('${d.path}/pubspec.yaml').deleteSync();
          writePackageJson();
          mockNodeUpgrade();

          await doUpgrade.exec(directory: d, ggLog: ggLog);

          expect(messages.join('\n'), contains('✓ Run »pnpm update --latest«'));
          verifyNever(
            () => processWrapper.run(
              'dart',
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          );
        });

        test('and the dart side both run for a hybrid', () async {
          // The whole point: a hybrid has two ecosystems, so both move.
          writePackageJson();
          mockNodeUpgrade();

          await doUpgrade.exec(directory: d, ggLog: ggLog);

          final all = messages.join('\n');
          expect(
            all,
            contains('✓ Run »dart pub upgrade --major-versions --tighten«'),
          );
          expect(all, contains('✓ Run »pnpm update --latest«'));
          // Dart first: a hybrid's npm lifecycle scripts may shell into it.
          expect(
            all.indexOf('dart pub upgrade'),
            lessThan(all.indexOf('pnpm update')),
          );
        });

        test('drops --latest with --no-major-versions', () async {
          writePackageJson();
          mockNodeUpgrade(majorVersions: false);
          mockDartPubUpgrade(majorVersions: false);

          await doUpgrade.exec(
            directory: d,
            ggLog: ggLog,
            majorVersions: false,
          );

          expect(messages.join('\n'), contains('✓ Run »pnpm update«'));
        });

        test('uses yarn when a yarn.lock is present', () async {
          writePackageJson(lockFile: 'yarn.lock');
          mockNodeUpgrade(executable: 'yarn', args: ['upgrade', '--latest']);

          await doUpgrade.exec(directory: d, ggLog: ggLog);

          expect(
            messages.join('\n'),
            contains('✓ Run »yarn upgrade --latest«'),
          );
        });

        test('uses npm when no lock file matches', () async {
          writePackageJson(lockFile: null);
          mockNodeUpgrade(executable: 'npm', args: ['update']);

          await doUpgrade.exec(directory: d, ggLog: ggLog);

          expect(messages.join('\n'), contains('✓ Run »npm update«'));
        });

        test('reports a failing node upgrade', () async {
          writePackageJson();
          mockNodeUpgrade(exitCode: 1, stderr: 'boom');

          await expectLater(
            doUpgrade.exec(directory: d, ggLog: ggLog),
            throwsA(
              isA<Exception>().having(
                (e) => rmControls(e.toString()),
                'message',
                contains('»pnpm update --latest« failed: boom'),
              ),
            ),
          );
        });

        test('holds typescript at 6 when the repo declares it', () async {
          // »pnpm update --latest« crosses every major boundary, and
          // TypeScript 7 is a breaking rewrite. The pin also brings a repo
          // that already drifted past it back down.
          writePackageJson(devDependencies: {'typescript': '~7.0.2'});
          mockNodeUpgrade();
          mockPin();

          await doUpgrade.exec(directory: d, ggLog: ggLog);

          final all = messages.join('\n');
          expect(all, contains('✓ Run »pnpm update --latest«'));
          expect(
            all,
            contains('✓ Run »pnpm update --save-exact typescript@6«'),
          );
          // The generic upgrade runs first, the pin corrects it afterwards.
          expect(
            all.indexOf('pnpm update --latest«'),
            lessThan(all.indexOf('--save-exact typescript@6')),
          );
        });

        test('does not pin a package the repo never declared', () async {
          // Installing it would add typescript as a new dependency.
          writePackageJson(devDependencies: {'prettier': '^3.0.0'});
          mockNodeUpgrade();

          await doUpgrade.exec(directory: d, ggLog: ggLog);

          expect(messages.join('\n'), isNot(contains('typescript@6')));
          verifyNever(
            () => processWrapper.run(
              any(),
              any(that: contains('typescript@6')),
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: any(named: 'runInShell'),
              environment: any(named: 'environment'),
            ),
          );
        });

        test('pins even with --no-major-versions', () async {
          // The pin states which version the repo must be on; it is not an
          // upgrade policy.
          writePackageJson(devDependencies: {'typescript': '~7.0.2'});
          mockNodeUpgrade(majorVersions: false);
          mockDartPubUpgrade(majorVersions: false);
          mockPin();

          await doUpgrade.exec(
            directory: d,
            ggLog: ggLog,
            majorVersions: false,
          );

          expect(
            messages.join('\n'),
            contains('✓ Run »pnpm update --save-exact typescript@6«'),
          );
        });

        test('reports a failing pin', () async {
          writePackageJson(devDependencies: {'typescript': '~7.0.2'});
          mockNodeUpgrade();
          mockPin(exitCode: 1, stderr: 'nope');

          await expectLater(
            doUpgrade.exec(directory: d, ggLog: ggLog),
            throwsA(
              isA<Exception>().having(
                (e) => rmControls(e.toString()),
                'message',
                contains(
                  '»pnpm update --save-exact typescript@6« failed: nope',
                ),
              ),
            ),
          );
        });

        test('restores a constraint the upgrade turned into a link:', () async {
          // pnpm resolves through the pnpm-workspace.yaml overrides and writes
          // the resolved spec back — so an upgrade silently replaces the
          // published constraint with a path nobody outside the workspace can
          // resolve, and »gg can merge« then refuses to merge it.
          writePackageJson(devDependencies: {'@org/sibling': '^1.0.1'});
          mockNodeUpgrade(
            onRun: () => File('${d.path}/package.json').writeAsStringSync(
              '{"name": "@org/test", "version": "1.0.0", "devDependencies": '
              '{"@org/sibling": "link:../sibling"}}',
            ),
          );

          await doUpgrade.exec(directory: d, ggLog: ggLog);

          expect(
            File('${d.path}/package.json').readAsStringSync(),
            contains('"@org/sibling": "^1.0.1"'),
          );
          expect(
            messages.join('\n'),
            contains('replaced the published constraint of @org/sibling'),
          );
        });

        test('leaves a spec that was local before the upgrade', () async {
          // Undoing a deliberate state is not the guard's job.
          writePackageJson(devDependencies: {'@org/sibling': 'link:../sib'});
          mockNodeUpgrade();

          await doUpgrade.exec(directory: d, ggLog: ggLog);

          expect(
            File('${d.path}/package.json').readAsStringSync(),
            contains('"@org/sibling": "link:../sib"'),
          );
          expect(
            messages.join('\n'),
            isNot(contains('replaced the published constraint')),
          );
        });

        test('restores a pnpm-workspace.yaml the upgrade rewrote', () async {
          // pnpm is known to rewrite »link:« specs to »file:«, which copies
          // instead of symlinking — sibling edits would stop propagating.
          const original = 'overrides:\n  "@org/sibling": link:../sibling\n';
          writePackageJson();
          File('${d.path}/pnpm-workspace.yaml').writeAsStringSync(original);
          mockNodeUpgrade(
            onRun: () => File('${d.path}/pnpm-workspace.yaml')
                .writeAsStringSync(
                  'overrides:\n  "@org/sibling": file:../sibling\n',
                ),
          );

          await doUpgrade.exec(directory: d, ggLog: ggLog);

          expect(
            File('${d.path}/pnpm-workspace.yaml').readAsStringSync(),
            original,
          );
          expect(
            messages.join('\n'),
            contains('The upgrade rewrote pnpm-workspace.yaml'),
          );
        });

        test('leaves an untouched pnpm-workspace.yaml alone', () async {
          const original = 'overrides:\n  "@org/sibling": link:../sibling\n';
          writePackageJson();
          File('${d.path}/pnpm-workspace.yaml').writeAsStringSync(original);
          mockNodeUpgrade();

          await doUpgrade.exec(directory: d, ggLog: ggLog);

          expect(
            File('${d.path}/pnpm-workspace.yaml').readAsStringSync(),
            original,
          );
          expect(messages.join('\n'), isNot(contains('The upgrade rewrote')));
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
