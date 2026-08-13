// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one_commit/src/tools/repository_url.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync();
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  group('readRepositoryUrl', () {
    group('Dart / Flutter', () {
      test('reads the repository URL from pubspec.yaml', () async {
        File('${tmp.path}/pubspec.yaml').writeAsStringSync(
          'name: foo\n'
          'version: 0.0.1\n'
          'repository: https://github.com/foo/bar\n',
        );
        expect(await readRepositoryUrl(tmp), 'https://github.com/foo/bar');
      });

      test('strips a trailing slash', () async {
        File('${tmp.path}/pubspec.yaml').writeAsStringSync(
          'name: foo\nrepository: https://github.com/foo/bar/\n',
        );
        expect(await readRepositoryUrl(tmp), 'https://github.com/foo/bar');
      });

      test('throws when pubspec.yaml has no repository key', () async {
        File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: foo\n');
        await expectLater(
          readRepositoryUrl(tmp),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls(e.toString()),
              'message',
              contains('No »repository:« found in pubspec.yaml'),
            ),
          ),
        );
      });
    });

    group('TypeScript', () {
      void writeTsProject(String packageJson) {
        File('${tmp.path}/package.json').writeAsStringSync(packageJson);
        File('${tmp.path}/tsconfig.json').writeAsStringSync('{}');
      }

      test('reads the repository URL from the object form', () async {
        writeTsProject(
          '{"name":"foo",'
          '"repository":{"type":"git",'
          '"url":"git+https://github.com/foo/bar.git"}}',
        );
        expect(await readRepositoryUrl(tmp), 'https://github.com/foo/bar');
      });

      test('reads the repository URL from the shorthand string form', () async {
        writeTsProject(
          '{"name":"foo","repository":"https://github.com/foo/bar.git"}',
        );
        expect(await readRepositoryUrl(tmp), 'https://github.com/foo/bar');
      });

      test('strips git+ prefix, .git suffix and trailing slash', () async {
        writeTsProject(
          '{"name":"foo",'
          '"repository":"git+https://github.com/foo/bar.git/"}',
        );
        expect(await readRepositoryUrl(tmp), 'https://github.com/foo/bar');
      });

      test('throws when repository key is missing', () async {
        writeTsProject('{"name":"foo"}');
        await expectLater(
          readRepositoryUrl(tmp),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls(e.toString()),
              'message',
              contains('No »repository« URL found in package.json'),
            ),
          ),
        );
      });

      test('throws when package.json is not a JSON object', () async {
        writeTsProject('[1, 2, 3]');
        await expectLater(
          readRepositoryUrl(tmp),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls(e.toString()),
              'message',
              contains('not a JSON object'),
            ),
          ),
        );
      });

      test('throws when the repository object has no url key', () async {
        writeTsProject('{"name":"foo","repository":{"type":"git"}}');
        await expectLater(readRepositoryUrl(tmp), throwsA(isA<Exception>()));
      });
    });

    group('without a manifest', () {
      test('throws', () async {
        await expectLater(
          readRepositoryUrl(tmp),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls(e.toString()),
              'message',
              contains('no manifest'),
            ),
          ),
        );
      });
    });

    test('resolves the real rljson fixture', () async {
      // Integration check against the actual test project in the workspace.
      final realProject = Directory(
        'P:/workspace_grace_cloud/tickets/'
        'feat-gg-typescript/real_testproject_rljson',
      );
      if (!realProject.existsSync()) return;

      expect(
        await readRepositoryUrl(realProject),
        'https://github.com/rljson/rljson',
      );
    });
  });
}
