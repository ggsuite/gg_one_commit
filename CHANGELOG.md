# Changelog

## 2.2.0 - 2026-08-09

### Changed

- Improve commit behavior
- Move gg commit conventions from gg_git to gg_one_core
- Record the doCommit state in system commits again

## 2.1.0 - 2026-08-09

### Changed

- `gg do upgrade deps` upgrades **every ecosystem a repository has**. A
`package.json` is now upgraded with the project's package manager
(`pnpm update [--latest]`, `yarn upgrade [--latest]`, `npm update`), and a
*hybrid* runs that in addition to `dart pub upgrade`. Before, the command
returned early without a `pubspec.yaml`, so a TypeScript repository was never
upgraded at all and a hybrid only ever saw its Dart side move. `--latest` is
gated on the existing `--major-versions` flag.
- The node upgrade holds the packages of `pinnedNpmVersions` at their fixed
version afterwards — today `typescript@6`. `pnpm update --latest` crosses every
major boundary, and TypeScript 7 is a breaking rewrite the toolchain is not
ready for, so the generic update is followed by
`pnpm update --save-exact typescript@6`, which also brings a repository that
already drifted past the pin back down (verified: a declared `~7.0.2` ends up
at `6.0.3`). No `--latest` on that second call — pnpm refuses it together with
an explicit spec (`ERR_PNPM_LATEST_WITH_SPEC`). The pin runs regardless of
`--major-versions` (it states which version the repository must be on, it is
not an upgrade policy) and only for packages the repository really declares —
installing one it never declared would add it.
- The Flutter executable is picked with `detectProjectType` instead of
`checkProjectType`. The latter reports *any* hybrid as TypeScript, so a hybrid
Flutter repository silently got `dart pub upgrade` and could not resolve its
`sdk: flutter` dependencies.
- A dependency spec the node upgrade turned into a **local** reference
(`link:`/`file:`/`workspace:`) is restored to the published constraint it had.
pnpm resolves a dependency through the `overrides` of `pnpm-workspace.yaml` and
writes the *resolved* spec back into `package.json`, so in a ticket workspace an
upgrade silently replaced e.g. `^1.0.1` with
`link:../../ggsuite/base_dna` — a path nobody outside the workspace can
resolve. `gg can merge` then refused to merge the repository, and publishing it
would have shipped a broken manifest. Specs that were already local before the
upgrade are left alone.
- A `pnpm-workspace.yaml` the node upgrade rewrote is restored, with a warning.
In a ticket workspace its `overrides` section redirects siblings to `link:../…`,
and pnpm is known to rewrite such specs to `file:` — which copies instead of
symlinking, so edits in a sibling would silently stop propagating mid-ticket.
- Allow to publish hybrid packages

## 2.0.0 - 2026-08-08

### Changed

- Allow to pass custom options to exec of dir commands.

## 1.0.1 - 2026-08-05

### Added

- Daily repo flows of the gg_one tool family, extracted from gg_one: the commit, push, dependency upgrade and ticket flows with their `can_*`/`did_*` counterparts, plus the ocean folder guard and the repository url helper.
- Add the missing example to each new package

### Changed

- Split gg_one into gg_one_core, gg_one_commit, gg_one_merge and gg_one_do_publish
