# Jarvis memory vault

Jarvis's long-term memory, stored as markdown in git. It's modelled on Instinct:
a background job writes it and the chat agent only reads it.

- `.hermes.md` is generated and injected at the start of every Hermes session.
  Don't edit it; run `python3 bin/build_context.py` after changing its sources.
- `system/chat.md` holds the chat agent's operating rules (the top of `.hermes.md`).
- `system/conventions.md` defines the file formats. The nightly job follows it.
- `profile.md`, `now.md` and `tasks.md` are rewritten nightly and snapshotted into `.hermes.md`.
- `people/`, `orgs/`, `projects/`, `places/`, `prefs/` hold one file per entity.
- `timeline/` holds one note per day.
- `inbox.md` is where the chat agent flags things during the day.
- `.dream/watermark` records the last message time the nightly job has processed.

Everything is in git. From the assistant repo on the Mac, `make vault-log` shows
what Jarvis learned each night. To undo a bad night, run `git revert` inside the
container (`make shell`, then `git -C /workspace revert HEAD`). Don't run git in
this folder on the host: the agent can write `.git/config`, which host git would
execute. Editing files by hand is fine.
Hand edits to profile/now/tasks show up in chat after `python3 bin/build_context.py`
and the next session or context compaction.

Forgetting removes information from the current files but not from git history.
To purge it completely, rewrite history (e.g. `git filter-repo`).
