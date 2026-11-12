<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Respect the repository settings in upgrade and can commit

## Motivation

- `do upgrade deps` always crossed major versions unless
  `--no-major-versions` was passed on every call
- Some repositories must stay on their current majors, and the flag was
  easy to forget — especially in flows that upgrade implicitly
- `can commit` always ran all checks, even in repositories where they are
  not wanted before a commit
- Both should be decided once per repository, in a tracked file

## Strategy

- Read the repository's `.gg/gg_rc` with `GgRc` from gg_one_core
- Apply each setting at the single place its behavior is decided, so every
  flow that goes through it follows automatically
- Keep the defaults: without a file, or with the defaults in it, nothing
  changes
- A flag given explicitly still wins over the file

## do upgrade deps

- `--[no-]major-versions` (or `majorVersions` from code) decides when it is
  given; otherwise `do.upgrade.deps.majorVersions` of `.gg/gg_rc` does
- The file is created with its defaults when missing
- `false` turns the upgrade into a minor one:
  - »dart pub upgrade --tighten« instead of »… --major-versions --tighten«
  - »pnpm update« / »yarn upgrade« instead of »… --latest«
- »do.upgrade.deps.majorVersions is false in .gg/gg_rc.« tells the user why
- `DoUpgradeDeps.effectiveMajorVersions(repo, explicit:)` gives callers the
  same answer, e.g. to name the flag in a commit message; it never writes
- The pins of `pinnedNpmVersions` still run, independent of the setting

## can commit

- `CanCommit` passes `checksSetting: GgRc.commitChecks`
- With `can.commit.checks: false` it runs none of its checks (pub get,
  analyze, format, build, tests, npm scripts, future versions), logs that
  they were skipped and records success
- `do commit` therefore commits everything without waiting for checks
- `can push` and `can publish` are not affected

## Dependency updates

- gg_one_core: `GgRc` reads `~/.gg_rc` and the repository's `.gg/gg_rc`;
  `CommandCluster` takes a `checksSetting`

## Open Points

- None
