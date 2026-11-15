# gg_one_commit

Daily repo flows of the gg_one tool family - committing, pushing, upgrading dependencies and creating ticket branches.

## Repository settings

The repository's `.gg/gg_rc` (gg_one_core's `GgRc`, created with its
defaults by `do upgrade deps` when missing):

```json
{
  "do": { "upgrade": { "deps": { "majorVersions": true } } },
  "can": { "commit": { "checks": false } }
}
```

- `do.upgrade.deps.majorVersions` — off by default: `do upgrade deps` runs
  without `--major-versions` / `--latest`. `true` lets the upgrade of this
  repository cross major versions. An explicit `--[no-]major-versions` still
  wins. A `.gg/gg_rc` written by an older version spells out `true`
- `can.commit.checks: false` — `can commit` skips its checks, so everything
  is committed
- Both belong to one repository: `~/.gg_rc` cannot set them
