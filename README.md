# gg_one_commit

Daily repo flows of the gg_one tool family - committing, pushing, upgrading dependencies and creating ticket branches.

## Repository settings

The repository's `.gg/gg_rc` (gg_one_core's `GgRc`, created with its
defaults by `do upgrade deps` when missing):

```json
{
  "do": { "upgrade": { "deps": { "majorVersions": false } } },
  "can": { "commit": { "checks": false } }
}
```

- `do.upgrade.deps.majorVersions: false` — `do upgrade deps` runs without
  `--major-versions` / `--latest`; an explicit `--[no-]major-versions` still
  wins
- `can.commit.checks: false` — `can commit` skips its checks, so everything
  is committed
- Both belong to one repository: `~/.gg_rc` cannot set them
