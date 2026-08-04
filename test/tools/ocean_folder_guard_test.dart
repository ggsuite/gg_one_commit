// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  // The guard looks at paths only, therefore none of these directories
  // needs to exist on disk.
  final root = Directory.systemTemp.path;

  Directory dir(List<String> segments) =>
      Directory(path.joinAll([root, ...segments]));

  group('isInOceanFolder', () {
    test('returns true for the ocean folder itself', () {
      expect(isInOceanFolder(dir(['.ocean'])), isTrue);
    });

    test('returns true for a repo inside the ocean folder', () {
      expect(isInOceanFolder(dir(['.ocean', 'ggsuite', 'gg_one'])), isTrue);
    });

    test('returns true for a repo inside the legacy ».master« folder', () {
      expect(isInOceanFolder(dir(['.master', 'ggsuite', 'gg_one'])), isTrue);
    });

    test('returns false for a repo inside a ticket workspace', () {
      expect(
        isInOceanFolder(dir(['tickets', '36_my_ticket', 'ggsuite', 'gg_one'])),
        isFalse,
      );
    });

    test('returns false for a folder only starting with ».ocean«', () {
      expect(isInOceanFolder(dir(['.ocean_backup', 'gg_one'])), isFalse);
    });

    test('returns false for a folder only starting with ».master«', () {
      expect(isInOceanFolder(dir(['.master_backup', 'gg_one'])), isFalse);
    });
  });

  group('throwWhenInOceanFolder', () {
    test('throws an actionable error inside the ocean folder', () {
      expect(
        () => throwWhenInOceanFolder(dir(['.ocean', 'ggsuite', 'gg_one'])),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            allOf(
              // The command in yellow, file names in green, the CLI commands
              // to run next in blue.
              contains('gg do commit'),
              contains('».ocean«'),
              contains('gg do checkout <ticket>'),
              contains('gg do commit --force'),
            ),
          ),
        ),
      );
    });

    test('names the legacy folder when thrown inside ».master«', () {
      expect(
        () => throwWhenInOceanFolder(dir(['.master', 'ggsuite', 'gg_one'])),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            allOf(contains('».master«'), contains('gg do commit --force')),
          ),
        ),
      );
    });

    test('does not throw outside of the ocean folder', () {
      expect(
        () => throwWhenInOceanFolder(
          dir(['tickets', '36_my_ticket', 'ggsuite', 'gg_one']),
        ),
        returnsNormally,
      );
    });
  });
}
