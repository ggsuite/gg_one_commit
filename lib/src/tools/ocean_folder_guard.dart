// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:path/path.dart' as path;

/// The name of the folder holding the pristine clones of a gg workspace.
const String oceanFolderName = '.ocean';

/// The former name of [oceanFolderName]. Still guarded so a workspace that
/// the tool has not auto-renamed yet keeps its protection.
const String legacyMasterFolderName = '.master';

/// The ocean folder segment of [directory]'s path — [oceanFolderName], the
/// legacy [legacyMasterFolderName], or null when the directory is in neither.
String? _matchedOceanFolder(Directory directory) {
  final segments = path.split(path.normalize(directory.absolute.path));
  if (segments.contains(oceanFolderName)) {
    return oceanFolderName;
  }
  if (segments.contains(legacyMasterFolderName)) {
    return legacyMasterFolderName;
  }
  return null;
}

/// Returns true when [directory] lies inside the workspace's ocean folder.
///
/// The check looks at the path only — any segment named [oceanFolderName]
/// (or the legacy [legacyMasterFolderName]) makes the directory an ocean
/// directory, no matter how deep it sits below it
/// (`<root>/.ocean/<org>/<repo>`).
bool isInOceanFolder(Directory directory) =>
    _matchedOceanFolder(directory) != null;

/// Throws when [directory] lies inside the workspace's ocean folder.
///
/// The ocean only mirrors the registered repositories; changes
/// belong into a ticket workspace (`<root>/tickets/<ticket>/<org>/<repo>`).
/// Callers skip the guard when »--force« is given — the message names that
/// escape hatch, so an ocean repo can still be fixed in place.
void throwWhenInOceanFolder(Directory directory) {
  final matchedFolder = _matchedOceanFolder(directory);
  if (matchedFolder == null) {
    return;
  }

  // The whole line is an error; only the folder and the commands to run
  // next carry their own semantic color.
  throw Exception(
    cError(
      'Cannot run '
      '${cCmd('gg do commit')}'
      ' inside the '
      '${cPath('»$matchedFolder«')}'
      ' folder.\n'
      'Switch to a ticket workspace, e.g. '
      '${cCmd('gg do checkout <ticket>')}'
      '\nOr commit anyway using '
      '${cCmd('gg do commit --force')}',
    ),
  );
}
