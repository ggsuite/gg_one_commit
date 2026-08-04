// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one_state/gg_one_state.dart';

/// Are all changes pushed to the remote repository?
class DidPush extends DidCommand {
  /// Constructor
  DidPush({
    super.name = 'push',
    super.description = 'Check if this repo was pushed',
    super.shortDescription = 'Changes are pushed to the git remote',
    super.suggestion = 'Please run »gg do push«.',
    super.stateKey = 'doPush',
    required super.ggLog,
  });
}

/// Mock for [DidPush]
class MockDidPush extends MockDidCommand implements DidPush {}
