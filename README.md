# gg_one_commit

Daily repo flows of the gg_one tool family - committing, pushing, upgrading dependencies and creating ticket branches.

## Per-repo settings

`.gg/gg_rc.jsonc` (created with its defaults when missing):

- `upgradeMajorVersions: false` — `do upgrade deps` runs without
  `--major-versions` / `--latest`
- `enableChecks: false` — `can commit` skips its checks, so everything is
  committed
