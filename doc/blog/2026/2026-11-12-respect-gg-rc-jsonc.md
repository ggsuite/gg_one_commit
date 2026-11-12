<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Respect .gg/gg_rc.jsonc in upgrade and can commit

## Motivation

- `do upgrade deps` always crossed major versions unless
  `--no-major-versions` was passed on every call
- Some repositories must stay on their current majors, and the flag was
  easy to forget — especially in flows that upgrade implicitly
- `can commit` always ran all checks, even in repositories where they are
  not wanted before a commit
- Both should be decided once per repository, in a tracked file

## Strategy

- Read the per-repository settings with `GgRc` from gg_one_core
- Apply them at the single place each behavior is decided, so every flow
  that goes through it follows automatically
- Keep the defaults: without a file, or with the defaults written into it,
  nothing changes

## do upgrade deps

- Before upgrading, `DoUpgradeDeps` loads `.gg/gg_rc.jsonc`; the file is
  created with its defaults when missing
- `upgradeMajorVersions: false` turns the upgrade into a minor one:
  - »dart pub upgrade --tighten« instead of »… --major-versions --tighten«
  - »pnpm update« / »yarn upgrade« instead of »… --latest«
- The line »upgradeMajorVersions is false in .gg/gg_rc.jsonc.« tells the
  user why
- The setting can only narrow: `--no-major-versions` still works when the
  file allows majors
- The pins of `pinnedNpmVersions` still run, independent of the setting

## can commit

- `CanCommit` is now a skippable command cluster
- With `enableChecks: false` it runs none of its checks (pub get, analyze,
  format, build, tests, npm scripts, future versions), logs that they were
  skipped and records success
- `do commit` therefore commits everything without waiting for checks
- `can push` and `can publish` are not affected

## Dependency updates

- gg_one_core: new `GgRc` settings reader and skippable `CommandCluster`

## Open Points

- None
