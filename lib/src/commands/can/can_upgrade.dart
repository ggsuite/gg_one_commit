// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one_state/gg_one_state.dart';
import 'package:gg_args/gg_args.dart';

/// Is the package ready to get a dependeny upgrade?
class CanUpgrade extends CommandCluster {
  /// Constructor
  CanUpgrade({
    required super.ggLog,
    super.name = 'upgrade',
    super.shortDescription = 'Can upgrade?',
    super.description = 'Check if this repo can be upgraded',
    super.stateKey = 'canUpgrade',
  }) : super(
         commands: [], // Currently we can upgrade always
       );
}

// .............................................................................
/// A mocktail mock
class MockCanUpgrade extends MockDirCommand<void> implements CanUpgrade {}
