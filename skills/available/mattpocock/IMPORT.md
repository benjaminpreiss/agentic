# Matt Pocock skills (vendored)

Source: https://github.com/mattpocock/skills, commit `4ae2317ddb22b046e26455e4f9c9b3aaaf62212d` (2026-11-01 import). Reviewed scope: `skills/engineering/`, `skills/misc/` and `skills/productivity/` only; no in-progress or deprecated skills, symlinks, Git metadata, or installer are imported; the stable skills' supporting scripts and templates are included. The upstream license is included as `LICENSE`.

`skills.sh` is a repository-preparation tool, **not** an activation hook: review changes from upstream before replacing this snapshot and commit the result. Never fetch mutable skills during a NixOS rebuild. To disable any one skill, remove its checked-in symlink from `skills/enabled/`; leave its source here for future use.
