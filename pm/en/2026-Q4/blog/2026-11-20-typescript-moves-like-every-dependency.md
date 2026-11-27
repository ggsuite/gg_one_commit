<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# TypeScript moves like every other dependency

## Motivation

- `do upgrade deps` held every npm package of gg_lang's
  `pinnedNpmVersions` at a fixed version — `typescript@6` — after the
  generic node update
- The pin ran regardless of `--[no-]major-versions`. A repository on
  TypeScript 5 was therefore lifted to 6 on every upgrade, even when it
  must not cross majors, e.g. because a framework it builds on does not
  support TypeScript 6 yet
- Whether an upgrade crosses major versions is already decided by
  `--[no-]major-versions` and `.gg/gg_rc`. A second, hard-coded rule for
  a single package undermined that decision

## Strategy

- Drop the pin step from the node upgrade
- Let `typescript` follow the same rule as every other dependency: within
  its range by default, across majors only when majors are allowed
- Keep the rest of the node upgrade unchanged: restoring localized specs
  and the `pnpm-workspace.yaml`

## Implementation

- `_runNodeUpgrade` runs the package manager's update command and nothing
  else — no `readNpmDependencyNames`, no `pinCommand` per pinned package
- The tests of the pin are replaced by one test: with majors allowed only
  `pnpm update --latest` runs, and no `--save-exact` follows
- CLAUDE.md no longer describes the pin

## Result

- `--no-major-versions`, or `majorVersions: false` in `.gg/gg_rc`, now
  keeps a repository on its TypeScript major
- With majors allowed, TypeScript may move to a new major like any other
  package. The checks that run after the upgrade decide whether the
  result can be committed
- One package-manager run less per upgrade

## Open Points

- None
