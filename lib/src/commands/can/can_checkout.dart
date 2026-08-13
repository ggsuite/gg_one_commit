// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one_core/gg_one_core.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_publish/gg_publish.dart';

/// Are the current changes ready for checking out a new branch?
class CanCheckout extends CommandCluster {
  /// Constructor
  CanCheckout({
    required super.ggLog,
    super.name = 'checkout',
    super.description = 'Check if this repo can be checked out',
    super.shortDescription = 'Can checkout?',
    super.stateKey = 'canCheckout',
    IsMainBranch? isMainBranch,
  }) : super(commands: [isMainBranch ?? IsMainBranch(ggLog: ggLog)]);
}

/// A mocktail mock
class MockCanCheckout extends MockDirCommand<void> implements CanCheckout {}
