// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one_state/gg_one_state.dart';
import 'dart:io';

import 'package:gg_log/gg_log.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:matcher/expect.dart';
import 'package:mocktail/mocktail.dart';

/// Are the dependencies of the package upgraded?
class DidUpgradeDependencies extends DidCommand {
  /// Constructor
  DidUpgradeDependencies({
    required super.ggLog,
    super.name = 'dependencies',
    super.description = 'Check if the dependencies were upgraded',
    super.shortDescription = 'Everything is upgraded',
    super.suggestion =
        'Not upgraded yet. Please run »gg do upgrade dependencies«.',
    super.stateKey = 'doCommit',
    IsUpgraded? isUpgraded,
  }) : _isUpgraded = isUpgraded ?? IsUpgraded(ggLog: ggLog);

  // ...........................................................................
  /// Returns previously set value
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
    bool? majorVersions,
    bool? ignoreUnstaged,
  }) async {
    /// Is everything upgraded?
    final isUpgraded = await _isUpgraded.get(
      directory: directory,
      ggLog: ggLog,
      majorVersions: majorVersions,
    );

    return isUpgraded;
  }

  // ######################
  // Private
  // ######################

  final IsUpgraded _isUpgraded;
}

/// Mock for [DidUpgradeDependencies]
class MockDidUpgradeDependencies extends MockDidCommand
    implements DidUpgradeDependencies {
  // ...........................................................................
  /// Mocks the result of the get command
  @override
  void mockGet({
    required bool result,
    Directory? directory,
    GgLog? ggLog,
    bool? majorVersions,
    bool doThrow = false,
    String? message,
  }) {
    when(
      () => get(
        ggLog: ggLog ?? any(named: 'ggLog'),
        directory: any(
          named: 'directory',
          that: predicate<Directory>(
            (d) => directory == null || d.path == directory.path,
          ),
        ),
        majorVersions: majorVersions,
      ),
    ).thenAnswer((invocation) async {
      return defaultReaction(
        doThrow: doThrow,
        invocation: invocation,
        result: result,
        message: message,
      );
    });
  }
}
