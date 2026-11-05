# Choose installed skills

Agentic installs only reviewed skills from [`skills/available/`](../skills/available/). Choose them in the symlink-free [`skills/enabled.nix`](../skills/enabled.nix):

```nix
[ "mattpocock/*" ]
```

`mattpocock/*` includes skills **recursively** under that directory. You can also select individual paths such as `mattpocock/engineering/code-review`. A skill's directory name becomes its installed name; duplicate names, missing `SKILL.md` files and paths outside `skills/available/` fail validation. Remove a selection to stop installing it without deleting the reviewed source. Wildcards expand from the **committed source**, not from a mutable remote repository.

Run `bash tests/deployment.sh` before proposing a change. An existing host still using the legacy [manual update](update.md) can run `bash tests/stage.sh`; its staging script recreates validated links *inside its private deployment copy* for compatibility. No symlinks enter commits staged by the shared toolkit. Agentic does not replace user-managed skills outside `~/.pi/agent/skills/agentic`.

Imported Matt Pocock skills are selected by default. See their [provenance](../skills/available/mattpocock/IMPORT.md) and the [selection decision](adr/0002-select-skills-with-a-manifest.md).
