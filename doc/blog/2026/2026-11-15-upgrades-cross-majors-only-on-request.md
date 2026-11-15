<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Upgrades cross major versions only on request

## Motivation

- `gg one do upgrade deps` runs `dart pub upgrade [--major-versions]
  --tighten` and the node equivalent
- Whether it crosses major versions comes from an explicit
  `--[no-]major-versions`, else from `do.upgrade.deps.majorVersions` in the
  repository's `.gg/gg_rc`
- gg_one_core changed the default of that setting from `true` to `false`.
  This repo documents the new default and tests both cases

## Strategy

- No change in the logic: `effectiveMajorVersions` reads the setting as
  before
- Update the doc comments, the README and the CLAUDE.md
- Make the tests say which case they test

## Documentation

- The doc comments of `DoUpgradeDeps` and `effectiveMajorVersions` name the
  default `false`
- The README explains the setting with `true` as the example: off by
  default, `true` lets the upgrade of the repository cross majors
- A `.gg/gg_rc` written by an older version spells out `true` and keeps it
- The class comment no longer names the commands that call the upgrade

## Tests

- Most tests of `do upgrade deps` are about an upgrade across majors. Their
  setUp now writes a `.gg/gg_rc` that allows them (`allowMajors`)
- A new test deletes the file and checks the default: »majorVersions is
  false«, `dart pub upgrade --tighten`, `pnpm update` without `--latest`
- The test of the written defaults deletes the file first
- `effectiveMajorVersions` answers `false` without a file and `true` with an
  explicit value

## Dependency updates

- gg_one_core: `do.upgrade.deps.majorVersions` defaults to `false`

## Open Points

- None
