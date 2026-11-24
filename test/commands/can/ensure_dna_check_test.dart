// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:helix/helix.dart'
    show
        MemoryDnaHost,
        dartDnaCheckPath,
        dartWrapperTest,
        flutterWrapperTest,
        tsDnaCheckPath,
        tsWrapperTest;
import 'package:test/test.dart';

void main() {
  const root = '/p';
  const dnaConfig = '{"version": 1, "layers": []}';
  const dartWithHelix =
      'name: p\ndev_dependencies:\n  helix: ^1.0.0\n  test: ^1.0.0\n';
  final messages = <String>[];

  setUp(messages.clear);

  Future<MemoryDnaHost> run(
    Map<String, String> files, {
    String? commitError,
  }) async {
    final host = MemoryDnaHost(files: files)..commitError = commitError;
    await EnsureDnaCheck(
      ggLog: messages.add,
      host: host,
    ).get(directory: Directory(root), ggLog: messages.add);
    return host;
  }

  group('EnsureDnaCheck', () {
    test('does nothing in a repository without a DNA', () async {
      final host = await run({'$root/pubspec.yaml': dartWithHelix});
      expect(host.existsFile('$root/$dartDnaCheckPath'), isFalse);
      expect(messages, isEmpty);
    });

    test('places and commits the Dart check where helix is declared', () async {
      final host = await run({
        '$root/pubspec.yaml': dartWithHelix,
        '$root/dna/_dna.json': dnaConfig,
      });
      expect(host.readString('$root/$dartDnaCheckPath'), dartWrapperTest);
      expect(messages.single, contains('Placed DNA check $dartDnaCheckPath'));
      expect(host.commits.single.paths, [dartDnaCheckPath]);
      expect(host.commits.single.message, EnsureDnaCheck.commitMessage);
    });

    test('names the test framework a check lacks', () async {
      await run({
        '$root/pubspec.yaml': 'name: p\ndev_dependencies:\n  helix: ^1.0.0\n',
        '$root/dna/_dna.json': dnaConfig,
      });
      expect(
        messages.single,
        contains(EnsureDnaCheck.notCheckedWarning('test')),
      );
    });

    test('keeps the placed check when it cannot commit it', () async {
      final host = await run({
        '$root/pubspec.yaml': dartWithHelix,
        '$root/dna/_dna.json': dnaConfig,
      }, commitError: 'not a git repository');
      expect(host.existsFile('$root/$dartDnaCheckPath'), isTrue);
      expect(messages.last, contains('Could not commit the DNA check'));
    });

    test('places the Flutter check where flutter_test tests', () async {
      final host = await run({
        '$root/pubspec.yaml':
            'name: p\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\n'
            '  helix: ^1.0.0\n',
        '$root/dna/_dna.json': dnaConfig,
      });
      expect(host.readString('$root/$dartDnaCheckPath'), flutterWrapperTest);
    });

    test('places the vitest check where helix-js is declared', () async {
      final host = await run({
        '$root/package.json':
            '{"devDependencies": {"@tssuite/helix-js": "^0.7.0", '
            '"vitest": "^4.0.0"}}',
        '$root/dna/_dna.json': dnaConfig,
      });
      expect(host.readString('$root/$tsDnaCheckPath'), tsWrapperTest);
    });

    test('replaces an older check and keeps a current one quietly', () async {
      final host = await run({
        '$root/pubspec.yaml': dartWithHelix,
        '$root/dna/_dna.json': dnaConfig,
        '$root/$dartDnaCheckPath': '// Placed by `helix init` — old\n',
      });
      expect(host.readString('$root/$dartDnaCheckPath'), dartWrapperTest);

      messages.clear();
      await EnsureDnaCheck(
        ggLog: messages.add,
        host: host,
      ).get(directory: Directory(root), ggLog: messages.add);
      expect(messages, isEmpty);
    });

    test('warns and places nothing without helix', () async {
      final host = await run({
        '$root/pubspec.yaml': 'name: p\ndev_dependencies:\n  test: ^1.0.0\n',
        '$root/dna/_dna.json': dnaConfig,
      });
      expect(host.existsFile('$root/$dartDnaCheckPath'), isFalse);
      expect(
        messages.single,
        contains(EnsureDnaCheck.notCheckedWarning('helix')),
      );
    });

    test('removes a placed check once helix is gone', () async {
      final host = await run({
        '$root/pubspec.yaml': 'name: p\ndev_dependencies:\n  test: ^1.0.0\n',
        '$root/dna/_dna.json': dnaConfig,
        '$root/$dartDnaCheckPath': dartWrapperTest,
      });
      expect(host.existsFile('$root/$dartDnaCheckPath'), isFalse);
      expect(messages.first, contains('Removed DNA check $dartDnaCheckPath'));
      expect(
        messages.last,
        contains(EnsureDnaCheck.notCheckedWarning('helix')),
      );
    });

    test('example() logs to print', () async {
      final printed = <String>[];
      await capturePrint(
        ggLog: printed.add,
        code: () async {
          final d = Directory.systemTemp.createTempSync('ensure_dna_check_');
          try {
            await EnsureDnaCheck.example().get(
              directory: d,
              ggLog: printed.add,
            );
          } finally {
            d.deleteSync(recursive: true);
          }
        },
      );
      expect(printed, isEmpty);
    });
  });
}
