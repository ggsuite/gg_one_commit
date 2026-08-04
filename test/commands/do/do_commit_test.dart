// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_changelog/gg_changelog.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one_commit/src/commands/can/can_commit.dart';
import 'package:gg_one_commit/src/commands/do/do_commit.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

// .............................................................................
/// Checks out an existing branch.
Future<void> checkout(Directory d, String branch) =>
    Checkout(ggLog: _noLog).get(directory: d, ggLog: _noLog, branch: branch);

/// Returns true when everything in [d] is committed.
Future<bool> isCommitted(Directory d) =>
    IsCommitted(ggLog: _noLog).get(directory: d, ggLog: _noLog);

void _noLog(String _) {}

// .............................................................................
/// Renames the current branch. gg_git has no command for this.
Future<void> renameBranch(Directory d, String branch) async {
  final result = await Process.run('git', [
    'branch',
    '-m',
    branch,
  ], workingDirectory: d.path);

  if (result.exitCode != 0) {
    throw Exception('Could not rename branch: ${result.stderr}');
  }
}

/// Detaches HEAD from the current branch. gg_git has no command for this.
Future<void> detachHead(Directory d) async {
  final result = await Process.run('git', [
    'checkout',
    '--detach',
  ], workingDirectory: d.path);

  if (result.exitCode != 0) {
    throw Exception('Could not detach HEAD: ${result.stderr}');
  }
}

void main() {
  late Directory d;
  late DoCommit doCommit;
  final messages = <String>[];
  // Strip the colors so the expectations assert the text, not the
  // escape codes. One closure instance — mocktail matches ggLog by
  // identity.
  // ignore: prefer_function_declarations_over_variables
  final GgLog ggLog = (String msg) => messages.add(rmControls(msg));
  late CommandRunner<void> runner;

  late CanCommit canCommit;

  // ...........................................................................
  void mockCanCommit() {
    registerFallbackValue(d);

    when(
      () => canCommit.exec(
        directory: any(named: 'directory'),
        ggLog: ggLog,
        force: null,
      ),
    ).thenAnswer((_) => Future.value());
  }

  // ...........................................................................
  setUp(() async {
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    await initCachedRepo(
      d,
      key: 'do_commit_base',
      build: (repo) async {
        await initGit(repo);

        // »gg do commit« refuses to run on the default branch
        await createBranch(repo, 'feature');

        await addAndCommitSampleFile(repo);

        // Insert CHANGELOG.md
        await addAndCommitSampleFile(
          repo,
          fileName: 'CHANGELOG.md',
          content: '# Changelog',
        );

        // Insert pubspec.yaml
        await addAndCommitSampleFile(
          repo,
          fileName: 'pubspec.yaml',
          content:
              'version: 1.0.0\n'
              'repository:https://github.com/inlavigo/gg.git',
        );
      },
    );

    // Mock stuff
    canCommit = MockCanCommit();
    mockCanCommit();

    // Create command
    doCommit = DoCommit(ggLog: ggLog, canCommit: canCommit);

    // Create runner
    runner = CommandRunner<void>('test', 'test');
    runner.addCommand(doCommit);
  });

  // ...........................................................................
  tearDown(() async {
    await d.delete(recursive: true);
  });

  group('DoCommit', () {
    group('exec(directory, ggLog, message)', () {
      group('should succeed', () {
        group('and log »✓ Committed«', () {
          test('when the command is executed the second time', () async {
            // Execute command the first time
            await doCommit.exec(
              directory: d,
              ggLog: ggLog,
              message: 'My commit',
              logType: LogType.added,
            );

            // Execute command the second time
            await doCommit.exec(
              directory: d,
              ggLog: ggLog,
              message: 'My commit 2',
              logType: LogType.added,
            );

            expect(messages.last, '✓ Committed');
          });
        });

        group('and stay silent', () {
          test('when the command is executed the first time '
              'but nothing needs to be committed.', () async {
            // Execute command the first time
            await doCommit.exec(
              directory: d,
              ggLog: ggLog,
              message: 'My commit',
              logType: LogType.added,
            );

            expect(messages, isEmpty);
          });
        });

        group('and commit silently', () {
          test('when the command is executed the first time '
              'and uncommitted changes were committed.', () async {
            // Add uncommitted file
            await addFileWithoutCommitting(d);

            // Execute command the first time
            await doCommit.exec(
              directory: d,
              ggLog: ggLog,
              message: 'My commit',
              logType: LogType.added,
            );

            expect(messages, isEmpty);
          });
        });

        group('and update CHANGELOG.md', () {
          group('when »updateChangeLog«', () {
            group('is not specified', () {
              test('programmatically', () async {
                // Add uncommitted file
                await addFileWithoutCommitting(d);

                // Execute command
                await doCommit.exec(
                  directory: d,
                  ggLog: ggLog,
                  message: 'My very special commit message',
                  logType: LogType.added,
                );

                // Check CHANGELOG.md
                final changelog = await File(
                  '${d.path}/CHANGELOG.md',
                ).readAsString();
                expect(changelog, contains('# Changelog\n'));
                expect(changelog, contains('## Unreleased\n'));
                expect(changelog, contains('## Added\n'));
                expect(changelog, contains('My very special commit message\n'));
              });

              test('via CLI', () async {
                // Add uncommitted file
                await addFileWithoutCommitting(d);

                // Execute command
                await runner.run([
                  'commit',
                  '-i',
                  d.path,
                  '-m',
                  'add My very special commit message',
                ]);

                // Check CHANGELOG.md
                final changelog = await File(
                  '${d.path}/CHANGELOG.md',
                ).readAsString();
                expect(changelog, contains('# Changelog\n'));
                expect(changelog, contains('## Unreleased\n'));
                expect(changelog, contains('## Added\n'));
                expect(changelog, contains('My very special commit message\n'));
              });
            });
            test('is true', () async {
              // Add uncommitted file
              await addFileWithoutCommitting(d);

              // Execute command the first time
              await doCommit.exec(
                directory: d,
                ggLog: ggLog,
                message: 'My very special commit message',
                logType: LogType.added,
                updateChangeLog: true,
              );

              // Check CHANGELOG.md
              final changelog = await File(
                '${d.path}/CHANGELOG.md',
              ).readAsString();
              expect(changelog, contains('# Changelog\n'));
              expect(changelog, contains('## Unreleased\n'));
              expect(changelog, contains('## Added\n'));
              expect(changelog, contains('My very special commit message\n'));
            });
          });
        });

        group('and not update CHANGELOG.md', () {
          test('when »updateChangeLog« is false', () async {
            // Add uncommitted file
            await addFileWithoutCommitting(d);

            // Check CHANGELOG.md before
            final changelogFile = File('${d.path}/CHANGELOG.md');
            final changeLogBefore = await changelogFile.readAsString();

            // ..........................................
            // Execute command with updateCHangeLog false
            await doCommit.exec(
              directory: d,
              ggLog: ggLog,
              message: 'My very special commit message',
              logType: LogType.added,
              updateChangeLog: false,
            );

            // Check CHANGELOG.md should not have changed
            final changeLogAfter = await changelogFile.readAsString();
            expect(changeLogBefore, changeLogAfter);

            // ..........................................
            // Execute command with updateCHangeLog true
            await updateAndCommitSampleFile(d);
            await doCommit.exec(
              directory: d,
              ggLog: ggLog,
              message: 'My very special commit message',
              logType: LogType.added,
              updateChangeLog: true,
            );

            // CHANGELOG.md should have changed
            final changeLogAfter1 = await changelogFile.readAsString();
            expect(changeLogAfter1, isNot(changeLogBefore));
          });

          test('when command is executed with --no-log option', () async {
            // Add uncommitted file
            await addFileWithoutCommitting(d);

            // Check CHANGELOG.md before
            final changelogFile = File('${d.path}/CHANGELOG.md');
            final changeLogBefore = await changelogFile.readAsString();

            // ....................................
            // Execute command with --no-log option
            await runner.run([
              'commit',
              '-i',
              d.path,
              'add',
              '-m',
              'My commit',
              '--no-log',
            ]);

            // Check CHANGELOG.md should not have changed
            final changeLogAfter = await changelogFile.readAsString();
            expect(changeLogBefore, changeLogAfter);

            // ..........................................
            // Execute command with --log option
            await updateAndCommitSampleFile(d);
            await runner.run([
              'commit',
              '-i',
              d.path,
              'add',
              '-m',
              'My commit',
              '--log',
            ]);

            // CHANGELOG.md should have changed
            final changeLogAfter1 = await changelogFile.readAsString();
            expect(changeLogAfter1, isNot(changeLogBefore));
          });
        });

        group('and allow to execute from cli', () {
          test('with message', () async {
            await addFileWithoutCommitting(d);
            await runner.run([
              'commit',
              '-i',
              d.path,
              'add',
              '-m',
              'My commit',
            ]);
            expect(messages, isEmpty);
          });
        });
        test('and have 100% code coverage', () {
          final instance = DoCommit(ggLog: ggLog);
          expect(instance, isNotNull);
        });

        group('when no commit message and no log type is provided', () {
          test('but everything is already committed', () async {
            // Add uncommitted file
            await addFileWithoutCommitting(d);

            // Execute command without messsage and log type.
            // It should fail, because we have uncommitted changes
            late String exception;

            try {
              await doCommit.exec(
                directory: d,
                ggLog: ggLog,
                message: null,
                logType: null,
              );
            } catch (e) {
              exception = rmControls(e.toString());
            }
            expect(
              exception,
              contains(rmControls(doCommit.helpOnMissingMessage)),
            );

            // Commit everything.
            // Run the command again without message and log type.
            // It should succeed, because everything is already committed.
            await commitFile(d, sampleFileName, message: 'Message');

            await doCommit.exec(
              directory: d,
              ggLog: ggLog,
              message: null,
              logType: null,
            );

            expect(messages, isEmpty);
          });
        });
      });

      group('should throw', () {
        test('when »git add finishes with an error', () async {
          // Mock the error
          final processWrapper = MockGgProcessWrapper();

          when(
            () => processWrapper.run('git', [
              'add',
              '.',
            ], workingDirectory: d.path),
          ).thenAnswer(
            (_) => Future.value(ProcessResult(1, 1, '', 'Some error')),
          );

          mockCanCommit();

          // Add an uncommitted file
          await addFileWithoutCommitting(d);

          // Execute the command
          final doCommit = DoCommit(
            ggLog: ggLog,
            canCommit: canCommit,
            processWrapper: processWrapper,
          );

          late String exception;

          try {
            await doCommit.exec(
              directory: d,
              ggLog: ggLog,
              message: 'My commit',
              logType: LogType.added,
            );
          } catch (e) {
            exception = rmControls(e.toString());
          }

          expect(exception, 'Exception: git add failed: Some error');
        });

        test('when »git commit finishes with an error', () async {
          // Make git commit failing
          final processWrapper = MockGgProcessWrapper();
          when(
            () => processWrapper.run('git', [
              'commit',
              '-m',
              'My commit',
            ], workingDirectory: d.path),
          ).thenAnswer(
            (_) => Future.value(ProcessResult(1, 1, '', 'Some error')),
          );

          // Make git add working
          when(
            () => processWrapper.run('git', [
              'add',
              '.',
            ], workingDirectory: d.path),
          ).thenAnswer((_) => Future.value(ProcessResult(1, 0, '', '')));

          mockCanCommit();

          // Add an uncommitted file
          await addFileWithoutCommitting(d);

          // Execute the command
          final doCommit = DoCommit(
            ggLog: ggLog,
            canCommit: canCommit,
            processWrapper: processWrapper,
          );

          late String exception;

          try {
            await doCommit.exec(
              directory: d,
              ggLog: ggLog,
              message: 'My commit',
              logType: LogType.added,
            );
          } catch (e) {
            exception = rmControls(e.toString());
          }

          expect(exception, 'Exception: git commit failed: Some error');
        });

        test('when no message is provided', () async {
          // Add an uncommitted file
          await addFileWithoutCommitting(d);

          // Execute the command
          final doCommit = DoCommit(ggLog: ggLog, canCommit: canCommit);

          late String exception;

          try {
            await doCommit.exec(
              directory: d,
              ggLog: ggLog,
              message: null, // no message
              logType: LogType.added,
            );
          } catch (e) {
            exception = rmControls(e.toString());
          }

          expect(
            exception,
            'Exception: ${rmControls(doCommit.helpOnMissingMessage)}',
          );
        });

        test('when pubspec.yaml does not contain a repo URL', () async {
          // Remove repository URL from pubspec.yaml
          await File(
            '${d.path}/pubspec.yaml',
          ).writeAsString('version: 1.0.0\n');

          await addFileWithoutCommitting(d);

          late String exception;

          try {
            await doCommit.exec(
              directory: d,
              ggLog: ggLog,
              message: 'My message',
              logType: LogType.fixed,
            );
          } catch (e) {
            exception = rmControls(e.toString());
          }

          expect(
            exception,
            'Exception: No »repository:« found in pubspec.yaml',
          );
        });

        group('when commits are not allowed on the current branch', () {
          Future<String> execAndCatch({bool? force}) async {
            await addFileWithoutCommitting(d);

            late String exception;

            try {
              await doCommit.exec(
                directory: d,
                ggLog: ggLog,
                message: 'My message',
                logType: LogType.fixed,
                force: force,
              );
            } catch (e) {
              exception = rmControls(e.toString());
            }

            // Nothing was committed
            expect(await isCommitted(d), isFalse);

            return exception;
          }

          test('- »main«', () async {
            await checkout(d, 'main');

            final exception = await execAndCatch();
            expect(exception, contains('Cannot commit on branch »main«.'));
            expect(exception, contains('gg do checkout <ticket>'));
            expect(exception, contains('gg do commit --force'));
          });

          test('- »master«', () async {
            await checkout(d, 'main');
            await renameBranch(d, 'master');

            final exception = await execAndCatch();
            expect(exception, contains('Cannot commit on branch »master«.'));
          });

          test('- but not with --force', () async {
            await checkout(d, 'main');
            await addFileWithoutCommitting(d);

            await doCommit.exec(
              directory: d,
              ggLog: ggLog,
              message: 'My message',
              logType: LogType.fixed,
              force: true,
            );

            expect(await isCommitted(d), isTrue);
          });

          test('- a detached HEAD', () async {
            await detachHead(d);

            final exception = await execAndCatch();
            expect(exception, contains('Cannot commit on a detached HEAD.'));
          });
        });
      });

      group('when the repo lies inside the ».ocean« folder', () {
        late Directory workspace;
        late Directory repo;

        setUp(() async {
          // The ocean mirrors the repos as .ocean/<org>/<repo>
          workspace = await Directory.systemTemp.createTemp();
          repo = Directory(
            path.join(workspace.path, '.ocean', 'ggsuite', 'gg_one'),
          );
          await repo.create(recursive: true);
          await initCachedRepo(
            repo,
            key: 'do_commit_ocean',
            build: (r) async {
              await initGit(r);

              // Not even a feature branch makes the ocean folder
              // committable
              await createBranch(r, 'feature');
              await addAndCommitSampleFile(r);
            },
          );
          await addFileWithoutCommitting(repo);
        });

        tearDown(() async {
          await workspace.delete(recursive: true);
        });

        test('should throw', () async {
          late String exception;

          try {
            await doCommit.exec(
              directory: repo,
              ggLog: ggLog,
              message: 'My message',
              logType: LogType.fixed,
            );
          } catch (e) {
            exception = rmControls(e.toString());
          }

          expect(exception, contains('gg do commit'));
          expect(exception, contains('».ocean«'));
          expect(exception, contains('gg do checkout <ticket>'));
          expect(exception, contains('gg do commit --force'));

          // Nothing was committed
          expect(await isCommitted(repo), isFalse);
        });

        test('should commit with --force', () async {
          await doCommit.exec(
            directory: repo,
            ggLog: ggLog,
            message: 'My message',
            logType: LogType.fixed,
            force: true,
          );

          expect(await isCommitted(repo), isTrue);
          expect(messages, isEmpty);
        });
      });

      group('special cases', () {
        group('- should be able to estimate log type from commit message', () {
          Future<void> runTest({
            required String keyWord,
            required String resultingLogType,
          }) async {
            // Add uncommitted file
            await addFileWithoutCommitting(d);

            // Execute command the first time
            await runner.run([
              'commit',
              '-i',
              d.path,
              '-m',
              'Did $keyWord something',
            ]);

            // Check CHANGELOG.md
            final changelog = await File(
              '${d.path}/CHANGELOG.md',
            ).readAsString();
            expect(changelog, contains('# Changelog\n'));
            expect(changelog, contains('## Unreleased\n'));
            expect(changelog, contains('## $resultingLogType\n'));
          }

          test('- unknown -> Changed', () async {
            await runTest(keyWord: 'unknown', resultingLogType: 'Changed');
          });

          test('- Change -> Changed', () async {
            await runTest(keyWord: 'Change', resultingLogType: 'Changed');
          });

          test('- Deprecate -> Deprecated', () async {
            await runTest(keyWord: 'Deprecate', resultingLogType: 'Deprecated');
          });

          test('- Fix -> Fixed', () async {
            await runTest(keyWord: 'Fix', resultingLogType: 'Fixed');
          });

          test('- Remove -> Removed', () async {
            await runTest(keyWord: 'Remove', resultingLogType: 'Removed');
          });

          test('- Secure -> Security', () async {
            await runTest(keyWord: 'Secure', resultingLogType: 'Security');
          });
        });
      });
    });
  });

  group('DoCommit on TypeScript project', () {
    setUp(() async {
      // Replace Dart project with a TypeScript one
      await File('${d.path}/pubspec.yaml').delete();
      await addAndCommitSampleFile(
        d,
        fileName: 'package.json',
        content: '{"name": "x"}',
      );
      await addAndCommitSampleFile(d, fileName: 'tsconfig.json', content: '{}');
    });

    test('should skip CHANGELOG.md update and commit successfully', () async {
      // Add uncommitted file
      await addFileWithoutCommitting(d);

      final changelogFile = File('${d.path}/CHANGELOG.md');
      final changeLogBefore = await changelogFile.readAsString();

      await doCommit.exec(
        directory: d,
        ggLog: ggLog,
        message: 'My commit',
        logType: LogType.added,
      );

      // CHANGELOG.md should not have been touched
      expect(await changelogFile.readAsString(), changeLogBefore);

      expect(messages, isEmpty);
    });
  });

  group('DoCommit on a project without a manifest', () {
    setUp(() async {
      // Remove the manifest — the project becomes ProjectType.none.
      await File('${d.path}/pubspec.yaml').delete();
      await commitFile(d, '.', message: 'Remove pubspec.yaml');
    });

    test('should skip CHANGELOG.md update and commit successfully', () async {
      // Add uncommitted file
      await addFileWithoutCommitting(d);

      final changelogFile = File('${d.path}/CHANGELOG.md');
      final changeLogBefore = await changelogFile.readAsString();

      await doCommit.exec(
        directory: d,
        ggLog: ggLog,
        message: 'My commit',
        logType: LogType.added,
      );

      // CHANGELOG.md should not have been touched
      expect(await changelogFile.readAsString(), changeLogBefore);

      expect(messages, isEmpty);
    });
  });

  group('DoCommit --force', () {
    test('should bypass checks and commit programmatically', () async {
      // Add uncommitted file
      await addFileWithoutCommitting(d);

      await doCommit.exec(
        directory: d,
        ggLog: ggLog,
        message: 'My force commit',
        logType: LogType.added,
        force: true,
      );

      // Should not have run checks
      verifyNever(
        () => canCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
          saveState: any(named: 'saveState'),
        ),
      );

      expect(messages, isEmpty);

      // Second call should reuse state
      await doCommit.exec(
        directory: d,
        ggLog: ggLog,
        message: 'My force commit',
        logType: LogType.added,
        force: true,
      );
      expect(messages.last, '✓ Committed');
    });

    test('should bypass checks and commit via CLI', () async {
      // Add uncommitted file
      await addFileWithoutCommitting(d);

      await runner.run([
        'commit',
        '-i',
        d.path,
        '--force',
        '-m',
        'add My force commit',
      ]);

      verifyNever(
        () => canCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
          saveState: any(named: 'saveState'),
        ),
      );

      expect(messages, isEmpty);
    });

    test('should bypass checks and set state when nothing to commit', () async {
      // Everything already committed here
      await doCommit.exec(
        directory: d,
        ggLog: ggLog,
        message: null,
        logType: null,
        force: true,
      );

      verifyNever(
        () => canCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
          saveState: any(named: 'saveState'),
        ),
      );

      expect(messages, isEmpty);

      // Run again to ensure state is used
      await doCommit.exec(
        directory: d,
        ggLog: ggLog,
        message: null,
        logType: null,
        force: true,
      );
      expect(messages.last, '✓ Committed');
    });
  });
}
