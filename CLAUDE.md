# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

`gg_one_commit` holds the daily flows of the gg_one tool family: commit, push, dependency upgrade and ticket creation, plus the `can_*`/`did_*` counterparts and the ocean folder guard.

The package is part of the gg_one tool family (see the `gg_one` umbrella repo for the family overview). All commands extend `DirCommand<T>` from `gg_args`; the primary logic lives in `get()`, and `exec()` delegates to it. `ggLog` is constructor-injected everywhere for testability.

## Behavior notes

- **`can/`** — readiness checks before an action. On the CLI only `can_commit`, `can_push` and `can_publish` are reachable. `can_merge`, `can_upgrade` and `can_checkout` are no longer registered — each has exactly one internal caller (gg_multi's `can publish`, `do_upgrade`, `create_ticket`), which constructs it directly, so the classes stay.
- **`did/`** — historical checks (was something done?): `did_commit`, `did_push`, `did_publish`, `did_upgrade`. `did publish` reads the hash-keyed `didPublish` state `do publish` records — »is what I have here released?« — under a **new** key name, because the legacy `doPublish` key is on `GgState.obsoleteKeys` and would be pruned on the next state write.
- **`do/`** — actions that execute with validation: `do_commit`, `do_push`, `do_publish`, `do_upgrade`, `create/`. `do upgrade deps` runs »dart pub upgrade [--major-versions] --tighten« (»flutter pub upgrade …« in a Flutter repo — plain `dart pub` cannot resolve `sdk: flutter` dependencies) — `--major-versions` is the default (`--no-major-versions` to opt out), `--tighten` is always on. It skips repos without a `pubspec.yaml` and reports by content hash whether anything changed (unchanged ⇒ »Everything is already up to date.«). It runs no checks of its own — the calling flows (`gg do push`, `gg do publish`) run `gg can commit` right afterwards. `do_configure_publish` is **not registered on the CLI**: `do_publish` calls it automatically when no configuration exists, and running it by hand only risked writing a config nobody asked for. The class stays.
  - `do_commit` refuses to run inside the workspace's `.ocean` folder (`tools/ocean_folder_guard.dart`: any path segment named `.ocean` — or the legacy `.master`, so a workspace the tool has not auto-renamed yet keeps its protection — so `<root>/.ocean/<org>/<repo>` counts) and unless HEAD is on a feature branch (gg_git's `IsFeatureBranch`: neither `main` nor `master`, and not a detached HEAD). Both guards run before every other step, and `--force` **bypasses both of them** — an ocean repo or a main branch can still be fixed in place, and both error messages name that escape hatch. The ocean only mirrors the repositories; work happens in a ticket workspace (`<root>/tickets/<ticket>/<org>/<repo>`), which is why gg_multi's own commit flows always operate on ticket repos and never hit the guard. Note that gg_multi's internal commit flows (`do add`, `do publish`) pass `force: true`, so they are exempt from the folder guard by construction.

## Testing Conventions

- 100% code coverage is required. Exempt lines with `// coverage:ignore-line` or `// coverage:ignore-start` / `// coverage:ignore-end`.
- Each implementation file must have a corresponding `_test.dart` in the mirrored path under `test/`.
- Mock classes are defined at the bottom of the **same file** as the class they mock, using `mocktail` and extending `MockDirCommand<T>`.
- Tests use `gg_git_test_helpers` (including the cached repo helpers) and `gg_capture_print`.
