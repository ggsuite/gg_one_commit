// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_changelog/gg_changelog.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() async {
  late Directory dLocal;
  late Directory dRemote;
  final messages = <String>[];
  // ignore: prefer_function_declarations_over_variables
  final GgLog ggLog = (String msg) => messages.add(rmControls(msg));

  late File ggJson;
  late DoPush doPush;
  late CanPush canPush;
  late CanCommit canCommit;
  late DoCommit doCommit;
  late IsPushed isPushed;

  // ...........................................................................
  void mockCanPush(bool success) {
    if (success) {
      when(
        () => canPush.exec(
          directory: any(named: 'directory'),
          ggLog: ggLog,
        ),
      ).thenAnswer((_) async => {});
      return;
    } else {
      when(
        () => canPush.exec(
          directory: any(named: 'directory'),
          ggLog: ggLog,
        ),
      ).thenThrow(Exception('Cannot push.'));
      return;
    }
  }

  // ...........................................................................
  setUp(() async {
    (dLocal, dRemote) = await initCachedRepoPair(
      key: 'do_push_base',
      build: (local, remote) async {
        await initLocalGit(local);
        await initRemoteGit(remote);
        await addRemoteToLocal(local: local, remote: remote);
        await enableEolLf(local);

        // gg commits — including the »#gg: Add .gg/gg.json check results«
        // state commit — exist on feature branches only; the default branch
        // receives release merges and tags.
        await createBranch(local, 'feature');

        await addAndCommitPubspecFile(local);
        await addAndCommitSampleFile(local);
        await pushLocalChangesUpstream(local, 'feature');

        // Init pubspec.yaml
        await File(join(local.path, 'pubspec.yaml'))
            .writeAsString('version: 1.0.0\nrepository: https://foo.com');
        await commitFile(local, 'pubspec.yaml');

        // Init CHANGELOG.md
        await File(join(local.path, 'CHANGELOG.md'))
            .writeAsString('# Changelog');
        await commitFile(local, 'CHANGELOG.md');
      },
    );
    registerFallbackValue(dLocal);

    canPush = MockCanPush();
    mockCanPush(true);
    doPush = DoPush(ggLog: ggLog, canPush: canPush);
    canCommit = MockCanCommit();

    doCommit = DoCommit(ggLog: ggLog, canCommit: canCommit);
    isPushed = IsPushed(ggLog: ggLog);
    ggJson = File(join(dLocal.path, '.gg', 'gg.json'));
  });

  // ...........................................................................
  tearDownAll(() async {
    await dLocal.delete(recursive: true);
    await dRemote.delete(recursive: true);
  });

  group('DoPush', () {
    group('exec', () {
      group('should succeed', () {
        group('and not push', () {
          group('when everything is already pushed', () {
            test('and the hashes are correct', () async {
              // Make a change that could be pushed
              await updateAndCommitSampleFile(dLocal);

              // Let check's pass
              mockCanPush(true);

              // Push the change the first time
              await doPush.exec(directory: dLocal, ggLog: ggLog);
              expect(messages.last, 'Checks successful. Pushed successful.');
              expect(
                await isPushed.get(directory: dLocal, ggLog: ggLog),
                isTrue,
              );

              // Execute the same push a second time
              await doPush.exec(directory: dLocal, ggLog: ggLog);
              expect(messages.last, 'Already checked and pushed.');
            });
          });
        });

        group('and push', () {
          test('and create an upstream branch, when not existing', () async {
            // Create a branch that does not exist on the remote
            const branchName = 'new-branch';
            await createBranch(dLocal, branchName);

            // Before the upstream branch should not exist
            final upstreamBranchBefore = await upstreamBranchName(dLocal);
            expect(upstreamBranchBefore, isEmpty);

            // Create a change
            await updateSampleFileWithoutCommitting(dLocal);

            // Commit the change using ggDoCommit
            when(() => canCommit.exec(directory: dLocal, ggLog: ggLog))
                .thenAnswer((_) async => {});
            await doCommit.exec(
              directory: dLocal,
              ggLog: ggLog,
              message: 'Message 0',
              logType: LogType.added,
            );

            // Push the change using ggDoPush
            await doPush.exec(directory: dLocal, ggLog: ggLog);

            // The changes should be pushed
            expect(await isPushed.get(directory: dLocal, ggLog: ggLog), isTrue);

            // The upstream branch should be set
            final upstreamBranchAfter = await upstreamBranchName(dLocal);
            expect(upstreamBranchAfter, 'origin/$branchName');
          });
          group('and overwrite the last pushed commit', () {
            test('when force or --force is specified', () async {
              // Make git push succeed
              final processWrapper = MockGgProcessWrapper();

              when(
                () => processWrapper.run('git', [
                  'push',
                  '-f',
                ], workingDirectory: dLocal.path),
              ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

              // Make a change that could be pushed
              await updateAndCommitSampleFile(dLocal);

              // Let check's pass
              mockCanPush(true);

              // Create the command
              final doPush = DoPush(
                ggLog: ggLog,
                canPush: canPush,
                processWrapper: processWrapper,
              );

              // Create a command runner
              final runner = CommandRunner<void>('test', 'test');
              runner.addCommand(doPush);

              // Execute the command
              await runner.run(['push', '--input', dLocal.path, '--force']);

              // Make sure the force flag is passed to git
              verify(
                () => processWrapper.run('git', [
                  'push',
                  '-f',
                ], workingDirectory: dLocal.path),
              ).called(1);
            });
          });

          group('a new hash', () {
            test('when before was not pushed with »gg do push«', () async {
              // Create a change
              await updateSampleFileWithoutCommitting(dLocal);

              // Commit the change using ggDoCommit
              when(() => canCommit.exec(directory: dLocal, ggLog: ggLog))
                  .thenAnswer((_) async => {});
              await doCommit.exec(
                directory: dLocal,
                ggLog: ggLog,
                message: 'Message 0',
                logType: LogType.added,
              );

              // Push the change without ggDoPush
              await pushLocalChanges(dLocal);
              expect(
                await isPushed.get(directory: dLocal, ggLog: ggLog),
                isTrue,
              );

              // Run ggDoPush should update .gg/gg.json
              final ggJsonBefore = await ggJson.readAsString();
              await doPush.exec(directory: dLocal, ggLog: ggLog);
              final ggJsonAfter = await ggJson.readAsString();
              expect(ggJsonBefore, isNot(ggJsonAfter));

              // The new gg.json should be pushed
              expect(
                await isPushed.get(directory: dLocal, ggLog: ggLog),
                isTrue,
              );
            });
          });
        });
      });

      group('and retry', () {
        const dropped = 'Connection to github.com closed by remote host.';

        /// Answers »git push« with [exitCodes], one per call.
        MockGgProcessWrapper mockPushSequence(
          List<int> exitCodes, {
          List<String> args = const ['push'],
        }) {
          final processWrapper = MockGgProcessWrapper();
          var call = 0;
          when(
            () =>
                processWrapper.run('git', args, workingDirectory: dLocal.path),
          ).thenAnswer((_) async {
            final exitCode = exitCodes[call++];
            return ProcessResult(1, exitCode, '', exitCode == 0 ? '' : dropped);
          });
          return processWrapper;
        }

        test('a push the remote dropped, until it succeeds', () async {
          final processWrapper = mockPushSequence([1, 0]);
          await updateAndCommitSampleFile(dLocal);
          mockCanPush(true);

          final doPush = DoPush(
            ggLog: ggLog,
            canPush: canPush,
            processWrapper: processWrapper,
            gitRetry: GitRetry.example,
          );
          await doPush.exec(directory: dLocal, ggLog: ggLog);

          verify(
            () => processWrapper.run('git', [
              'push',
            ], workingDirectory: dLocal.path),
          ).called(2);
          expect(
            messages,
            anyElement(contains('git push failed with a transient network')),
          );
          expect(messages.last, 'Checks successful. Pushed successful.');
        });

        test('creating an upstream branch the remote dropped', () async {
          const branchName = 'new-branch';
          await createBranch(dLocal, branchName);
          final processWrapper = mockPushSequence(
            [1, 0],
            args: ['push', '--set-upstream', 'origin', branchName],
          );
          await updateAndCommitSampleFile(dLocal);
          mockCanPush(true);

          final doPush = DoPush(
            ggLog: ggLog,
            canPush: canPush,
            processWrapper: processWrapper,
            gitRetry: GitRetry.example,
          );
          await doPush.exec(directory: dLocal, ggLog: ggLog);

          verify(
            () => processWrapper.run('git', [
              'push',
              '--set-upstream',
              'origin',
              branchName,
            ], workingDirectory: dLocal.path),
          ).called(2);
          expect(
            messages,
            anyElement(contains('origin $branchName failed with a transient')),
          );
        });

        test('and give up when the remote keeps dropping the push', () async {
          final processWrapper = mockPushSequence([1, 1, 1]);
          await updateAndCommitSampleFile(dLocal);
          mockCanPush(true);

          final doPush = DoPush(
            ggLog: ggLog,
            canPush: canPush,
            processWrapper: processWrapper,
            gitRetry: GitRetry.example,
          );
          late String exception;
          try {
            await doPush.exec(directory: dLocal, ggLog: ggLog);
          } catch (e) {
            exception = rmControls(e.toString());
          }

          expect(exception, 'Exception: git push failed: $dropped');
          verify(
            () => processWrapper.run('git', [
              'push',
            ], workingDirectory: dLocal.path),
          ).called(3);
        });
      });

      group('should throw', () {
        test('when canPush throws', () async {
          // Make a change that could be pushed
          await updateAndCommitSampleFile(dLocal);

          // Let canPush fail
          mockCanPush(false);

          // Execute doPoush -> should fail
          late String exception;
          try {
            await doPush.exec(directory: dLocal, ggLog: ggLog);
          } catch (e) {
            exception = rmControls(e.toString());
          }

          expect(exception, 'Exception: Cannot push.');
        });

        test('when »git push« throws', () async {
          // Make git fail
          final processWrapper = MockGgProcessWrapper();

          when(
            () => processWrapper.run('git', [
              'push',
            ], workingDirectory: dLocal.path),
          ).thenAnswer((_) async => ProcessResult(1, 1, '', 'Some error'));

          // Let check's pass
          mockCanPush(true);

          // Make a change that could be pushed
          await updateAndCommitSampleFile(dLocal);

          // Create the command
          final doPush = DoPush(
            ggLog: ggLog,
            canPush: canPush,
            processWrapper: processWrapper,
          );

          // Execute the command
          late String exception;
          try {
            await doPush.exec(directory: dLocal, ggLog: ggLog);
          } catch (e) {
            exception = rmControls(e.toString());
          }

          expect(exception, 'Exception: git push failed: Some error');

          // A real error is not retried.
          verify(
            () => processWrapper.run('git', [
              'push',
            ], workingDirectory: dLocal.path),
          ).called(1);
        });

        test('when creating an upstream branch fails', () async {
          // Create a branch that does not exist on the remote
          const branchName = 'new-branch';
          await createBranch(dLocal, branchName);

          // Make git push fail
          final processWrapper = MockGgProcessWrapper();

          when(
            () => processWrapper.run('git', [
              'push',
              '--set-upstream',
              'origin',
              branchName,
            ], workingDirectory: dLocal.path),
          ).thenAnswer((_) async => ProcessResult(1, 1, '', 'Some error'));

          // Create the command
          final doPush = DoPush(
            ggLog: ggLog,
            canPush: canPush,
            processWrapper: processWrapper,
          );

          // Execute the command
          late String exception;
          try {
            await doPush.exec(directory: dLocal, ggLog: ggLog);
          } catch (e) {
            exception = rmControls(e.toString());
          }

          expect(
            exception,
            'Exception: git push --set-upstream origin $branchName failed: '
            'Some error',
          );
        });
      });
    });

    test('should have a code coverage of 100%', () {
      DoPush(ggLog: ggLog);
    });
  });
}
