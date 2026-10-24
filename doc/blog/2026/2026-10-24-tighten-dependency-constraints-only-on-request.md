<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Tighten dependency constraints only on request

## Motivation

- `do upgrade deps` keeps the dependencies of a repo current, and callers
  run it again and again while a ticket is worked on
- It always ran `dart pub upgrade [--major-versions] --tighten`
- In a ticket workspace that crashed inside pub (`Entrypoint.tighten`):
  `Minimum version ("0.5.3") must be less than maximum ("0.5.0-0")`
- A crashing upgrade blocks every flow that calls it
- Raising the lower bounds is right for a release, against the registry,
  but not against local checkouts
- Callers also want to know up front whether a commit of a repo uses a
  message at all, so they do not ask the user for one in vain

## Strategy

- Find out why pub builds an impossible range
- Make tightening an explicit choice, off by default
- Keep everything else of the upgrade as it is
- Let the mock take the new parameter, so callers can test their call
- Expose the decision `DoCommit` already makes about messages

## Implementation 1: Make tightening opt-in

- In a ticket workspace `pubspec_overrides.yaml` points sibling
  dependencies at their local checkouts
- `--major-versions` does not raise every constraint, e.g. not that of a
  git dependency declared `^0.4.0`
- `--tighten` raises the lower bound to the resolved version, which is the
  newer local one, but keeps the old upper bound:

```text
declared         ^0.4.0             (>=0.4.0 <0.5.0-0)
local override   0.5.3
tightened        >=0.5.3 <0.5.0-0   -> pub crashes
```

- During a ticket the overrides always exist; they are removed only right
  before a publish, so only there is tightening safe
- `DoUpgradeDeps` gets the flag `--[no-]tighten`, off by default
- `exec` and `get` take a parameter `tighten`; without it the flag decides
- `--tighten` is passed to `dart pub upgrade` or `flutter pub upgrade`
  only when it is on: `dart pub upgrade [--major-versions] [--tighten]`
- The node side has no equivalent; pnpm, yarn and npm run as before
- `MockDoUpgradeDeps.mockExec` and `mockGet` accept `tighten`
- Tests cover the default, `tighten: true`, `--tighten` and `--no-tighten`

## Implementation 2: Tell whether a commit needs a message

- New `DoCommit.needsMessage(directory, ggLog, force)`
- `true` for uncommitted changes
- `false` for a repo the command has committed already, also with `force`
- Otherwise `true` for commits not recorded yet that need a CHANGELOG
  entry, and always with `force`
- `false` when the new commits are `#gg:` bookkeeping only
- A caller can skip the message prompt for a repo with nothing to commit

## Dependency updates

- `dna_ggsuite` ^1.0.0 regenerated the guides, skills and `CLAUDE.md`
  block: a `/gg-review` skill, the rules to describe every repo in its own
  terms and to keep every repo in its scope and its `index.jsonc` current,
  hooks that keep the prompts in the project management repo, and type
  names without a package prefix

## Result

- `do upgrade deps` runs in a ticket workspace without crashing
- Constraints are tightened only where a caller asks for it

## Open Points

- Callers that publish have to pass `tighten: true` themselves; one that
  forgets it releases loose lower bounds without any warning
- `--tighten` with overrides in place still crashes inside pub; the
  command does not refuse that combination
