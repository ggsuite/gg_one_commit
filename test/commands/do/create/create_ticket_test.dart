// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  final messages = <String>[];
  final ggLog = messages.add;
  late CommandRunner<void> runner;
  late CreateTicket createTicket;
  late MockCanCheckout canCheckout;
  late MockIsPushed isPushed;
  late MockGgProcessWrapper processWrapper;

  setUp(() async {
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    registerFallbackValue(d);
    canCheckout = MockCanCheckout();
    isPushed = MockIsPushed();
    processWrapper = MockGgProcessWrapper();
    canCheckout.mockExec(result: null, directory: d, ggLog: ggLog);
    createTicket = CreateTicket(
      ggLog: ggLog,
      canCheckout: canCheckout,
      isPushed: isPushed,
      processWrapper: processWrapper,
    );
    runner = CommandRunner<void>('gg', 'gg')..addCommand(createTicket);
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  void mockGitCommand(
    List<String> args, {
    int exitCode = 0,
    String stdout = '',
    String stderr = '',
  }) {
    when(
      () => processWrapper.run('git', args, workingDirectory: d.path),
    ).thenAnswer((_) async => ProcessResult(0, exitCode, stdout, stderr));
  }

  /// Mocks a dirty worktree, i.e. »git stash create« returns a commit hash.
  void mockStash(String branchName) {
    mockGitCommand(['stash', 'create'], stdout: 'abc123\n');
    mockGitCommand(['stash', 'push', '-m', 'gg:$branchName']);
    mockGitCommand(['stash', 'pop']);
  }

  group('CreateTicket', () {
    test('should execute CanCheckout before git commands', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      mockStash('feat_test');
      mockGitCommand(['checkout', '-b', 'feat_test']);

      await createTicket.exec(
        directory: d,
        ggLog: ggLog,
        branchName: 'feat_test',
      );

      verify(() => canCheckout.exec(directory: d, ggLog: ggLog)).called(1);
    });

    test('should reset soft when unpushed commits exist', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => false);

      mockGitCommand(['reset', '--soft', 'origin/main']);
      mockStash('feat_test');
      mockGitCommand(['checkout', '-b', 'feat_test']);

      await createTicket.exec(
        directory: d,
        ggLog: ggLog,
        branchName: 'feat_test',
      );

      verify(() => canCheckout.exec(directory: d, ggLog: ggLog)).called(1);
      verify(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'reset',
          '--soft',
          'origin/main',
        ], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'stash',
          'push',
          '-m',
          'gg:feat_test',
        ], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'checkout',
          '-b',
          'feat_test',
        ], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'stash',
          'pop',
        ], workingDirectory: d.path),
      ).called(1);
    });

    test('should skip reset when everything is pushed', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      mockStash('feat_test');
      mockGitCommand(['checkout', '-b', 'feat_test']);

      await createTicket.exec(
        directory: d,
        ggLog: ggLog,
        branchName: 'feat_test',
      );

      verify(() => canCheckout.exec(directory: d, ggLog: ggLog)).called(1);
      verifyNever(
        () => processWrapper.run('git', [
          'reset',
          '--soft',
          'origin/main',
        ], workingDirectory: d.path),
      );
      verify(
        () => processWrapper.run('git', [
          'stash',
          'push',
          '-m',
          'gg:feat_test',
        ], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'checkout',
          '-b',
          'feat_test',
        ], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'stash',
          'pop',
        ], workingDirectory: d.path),
      ).called(1);
    });

    test('should support CLI usage', () async {
      when(
        () => isPushed.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      mockStash('feat_cli');
      mockGitCommand(['checkout', '-b', 'feat_cli']);

      await runner.run([
        'ticket',
        '-i',
        d.path,
        '-m',
        'CLI message',
        'feat_cli',
      ]);

      verify(
        () => processWrapper.run('git', [
          'checkout',
          '-b',
          'feat_cli',
        ], workingDirectory: d.path),
      ).called(1);

      final ticketFile = File('${d.path}${Platform.pathSeparator}ticket.json');
      expect(ticketFile.existsSync(), isTrue);

      final content =
          jsonDecode(ticketFile.readAsStringSync()) as Map<String, dynamic>;
      expect(content['issue_id'], equals('feat_cli'));
      expect(content['description'], equals('CLI message'));
    });

    test('should pop stash and rethrow when checkout fails', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      mockStash('feat_test');
      mockGitCommand(
        ['checkout', '-b', 'feat_test'],
        exitCode: 1,
        stderr: 'Checkout error',
      );

      await expectLater(
        () => createTicket.exec(
          directory: d,
          ggLog: ggLog,
          branchName: 'feat_test',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'toString()',
            'Exception: git checkout -b feat_test failed: Checkout error',
          ),
        ),
      );

      verify(() => canCheckout.exec(directory: d, ggLog: ggLog)).called(1);
      verify(
        () => processWrapper.run('git', [
          'stash',
          'push',
          '-m',
          'gg:feat_test',
        ], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'checkout',
          '-b',
          'feat_test',
        ], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'stash',
          'pop',
        ], workingDirectory: d.path),
      ).called(1);
    });

    test('should throw when CanCheckout fails', () async {
      canCheckout.mockExec(
        result: null,
        directory: d,
        ggLog: ggLog,
        doThrow: true,
        message: 'Cannot checkout.',
      );

      await expectLater(
        () => createTicket.exec(
          directory: d,
          ggLog: ggLog,
          branchName: 'feat_test',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'toString()',
            contains('Cannot checkout.'),
          ),
        ),
      );

      verifyNever(
        () => processWrapper.run(
          'git',
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
    });

    test('should throw when stash push fails', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      mockGitCommand(['stash', 'create'], stdout: 'abc123\n');
      mockGitCommand(
        ['stash', 'push', '-m', 'gg:feat_test'],
        exitCode: 1,
        stderr: 'Some error',
      );

      expect(
        () => createTicket.exec(
          directory: d,
          ggLog: ggLog,
          branchName: 'feat_test',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'toString()',
            'Exception: git stash push failed: Some error',
          ),
        ),
      );
    });

    test('should throw when stash create fails', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      mockGitCommand(['stash', 'create'], exitCode: 1, stderr: 'Some error');

      await expectLater(
        () => createTicket.exec(
          directory: d,
          ggLog: ggLog,
          branchName: 'feat_test',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'toString()',
            'Exception: git stash create failed: Some error',
          ),
        ),
      );
    });

    test('should not stash nor restore when the worktree is clean', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      // An empty »git stash create« output means: nothing to stash.
      mockGitCommand(['stash', 'create']);
      mockGitCommand(['checkout', '-b', 'feat_test']);

      await createTicket.exec(
        directory: d,
        ggLog: ggLog,
        branchName: 'feat_test',
      );

      verify(
        () => processWrapper.run('git', [
          'checkout',
          '-b',
          'feat_test',
        ], workingDirectory: d.path),
      ).called(1);
      verifyNever(
        () => processWrapper.run('git', [
          'stash',
          'push',
          '-m',
          'gg:feat_test',
        ], workingDirectory: d.path),
      );
      verifyNever(
        () => processWrapper.run('git', [
          'stash',
          'pop',
        ], workingDirectory: d.path),
      );
    });

    test('should not restore a foreign stash when checkout fails on a clean '
        'worktree', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      mockGitCommand(['stash', 'create']);
      mockGitCommand(
        ['checkout', '-b', 'feat_test'],
        exitCode: 1,
        stderr: 'Checkout error',
      );

      await expectLater(
        () => createTicket.exec(
          directory: d,
          ggLog: ggLog,
          branchName: 'feat_test',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'toString()',
            'Exception: git checkout -b feat_test failed: Checkout error',
          ),
        ),
      );

      verifyNever(
        () => processWrapper.run('git', [
          'stash',
          'pop',
        ], workingDirectory: d.path),
      );
    });

    test('should throw when issue id is missing on CLI', () async {
      expect(
        () => runner.run(['ticket', '-i', d.path, '-m', 'CLI message']),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            'Missing issue id parameter.',
          ),
        ),
      );
    });

    test('should throw when issue id is missing programmatically', () async {
      expect(
        () => createTicket.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            'Missing issue id parameter.',
          ),
        ),
      );
    });

    test('should throw on CLI when message is missing', () async {
      expect(
        () => runner.run(['ticket', '-i', d.path, 'feat_cli']),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Option message is mandatory.',
          ),
        ),
      );
    });

    test(
      'should write ticket.json file when message is provided programmatically',
      () async {
        when(
          () => isPushed.get(
            directory: d,
            ggLog: ggLog,
            ignoreUnCommittedChanges: true,
          ),
        ).thenAnswer((_) async => true);

        mockStash('feat_test');
        mockGitCommand(['checkout', '-b', 'feat_test']);

        await createTicket.exec(
          directory: d,
          ggLog: ggLog,
          branchName: 'feat_test',
          message: 'Programmatic message',
        );

        final ticketFile = File(
          '${d.path}${Platform.pathSeparator}ticket.json',
        );
        expect(ticketFile.existsSync(), isTrue);

        final content =
            jsonDecode(ticketFile.readAsStringSync()) as Map<String, dynamic>;
        expect(content['issue_id'], equals('feat_test'));
        expect(content['description'], equals('Programmatic message'));
      },
    );

    test(
      'should not write ticket.json file when message is null programmatically',
      () async {
        when(
          () => isPushed.get(
            directory: d,
            ggLog: ggLog,
            ignoreUnCommittedChanges: true,
          ),
        ).thenAnswer((_) async => true);

        mockStash('feat_test');
        mockGitCommand(['checkout', '-b', 'feat_test']);

        await createTicket.exec(
          directory: d,
          ggLog: ggLog,
          branchName: 'feat_test',
        );

        final ticketFile = File(
          '${d.path}${Platform.pathSeparator}ticket.json',
        );
        expect(ticketFile.existsSync(), isFalse);
      },
    );
  });
}

class MockGgProcessWrapper extends Mock implements GgProcessWrapper {}
