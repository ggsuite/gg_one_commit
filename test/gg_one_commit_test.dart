// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:test/test.dart';

void main() {
  group('GgOneCommit()', () {
    group('foo()', () {
      test('should return foo', () async {
        const ggOneCommit = GgOneCommit();
        expect(ggOneCommit.foo(), 'foo');
      });
    });
  });
}
