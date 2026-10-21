# Jarvis: a personal Hermes assistant over iMessage

Hermes Agent runs in a locked-down Docker container on an always-on Mac. You
talk to it over iMessage (and Discord). It remembers you through a git-tracked
markdown vault, modelled on how Instinct does memory: the chat agent reads the
vault, and a nightly background job consolidates each day's conversations
into it.

```
 iPhone ── iMessage ──▶ Messages.app ◀──▶ BlueBubbles Server        (native macOS)
                                                │ ▲
                  REST: host.docker.internal:1234 │ webhook: localhost:8645 (loopback only)
                                                ▼ │
 ┌─────────────────────── Docker: hermes-agent ───────────────────────┐
 │ gateway: iMessage + Discord + cron scheduler                        │
 │   /workspace    ← ~/jarvis-vault (git): profile, people, timeline…  │
 │   /opt/data     ← Hermes state: config, auth, sessions (state.db)   │
 │ 04:00 nightly: jarvis-dream reads the day's messages → updates vault │
 └─────────────────────────────────────────────────────────────────────┘
 05:00 (host, launchd): vault → host-owned mirror → private GitHub repo
```

## What's in this repo

| Path | Purpose |
|------|---------|
| `compose.yaml` | The container: vault and state mounts, loopback webhook port, timezone, git identity |
| `hermes/SOUL.md` | Jarvis's identity, copied into Hermes by `make configure` |
| `hermes/skills/jarvis-dream/` | Procedure for the nightly consolidation (mounted read-only) |
| `hermes/scripts/jarvis_dream_collect.py` | Pre-run script: new messages, inbox and vault index for the nightly job (mounted read-only) |
| `vault-template/` | Starting contents of the memory vault (`make vault-init`) |
| `scripts/` | Everything behind the `make` targets |
| `tests/` | `make test`: throwaway end-to-end test with a fake BlueBubbles server |

## How memory works

- **At the start of every session** Hermes injects `/workspace/.hermes.md`,
  which contains the operating rules plus a snapshot of `profile.md`,
  `now.md` and `tasks.md`.
- **During the day**, the chat agent looks things up with `rg` over the vault
  (every file has `aliases:`) and uses `session_search` for today's
  conversations. It can only append to `inbox.md` and edit `tasks.md`.
- **Every night at 04:00**, the `jarvis-dream` job receives every message since
  the last run. It:
  - updates entity files and writes a timeline note per day
  - processes the inbox, including `FORGET:` requests
  - rewrites `now.md` and `profile.md`
  - regenerates `.hermes.md` and commits

  On Sundays it also merges duplicates and prunes stale facts. If nothing is
  new, it skips the model call entirely.
- **Hermes rejects any job prompt that looks like prompt injection.** If one of
  your messages trips that filter (a jailbreak meme, a pasted phishing email),
  the collector withholds that line. Otherwise the nightly job would be blocked
  every night from then on.
- A running conversation picks up the refreshed snapshot at its next context
  compaction, or immediately if you text `/new`.

Hermes's built-in `MEMORY.md`/`USER.md` are turned off, so the vault is the
single source of truth. On its first run, the nightly job imports anything
already in them.

## Setting up the Mac

### 1. Host

```sh
make host-setup   # sudo: never sleep on AC; macOS updates download but wait for you
```

Keep FileVault on. Because updates no longer install on their own, the Mac
only reboots when you choose to, so install updates when you're home. After any
reboot, log in at the Mac, and Jarvis is back.

Then, by hand (`host-setup` prints this list too):

- Docker Desktop → *Start Docker Desktop when you sign in*
- Tailscale → signed in, *Launch at login*
- System Settings → Sharing → **Remote Login** and **Screen Sharing** on
- Keep the lid open and stay logged in; screen lock is fine

### 2. iMessage bridge

1. **Apple ID.** Create a separate Apple ID for Jarvis, sign in to Messages
   with it, and text it once from your phone. Save it as a contact called
   "Jarvis".
2. **BlueBubbles Server.** Install it from [bluebubbles.app](https://bluebubbles.app/)
   and grant the permissions it asks for (Full Disk Access, Accessibility).
   - For the connection method, choose **LAN / no proxy**.
   - Skip the Google/Firebase step.
   - Set a strong password and enable *Start at login*.
   - Leave the **Private API** off: it needs SIP disabled, which isn't worth
     typing indicators.

### 3. Hermes and the vault

```sh
git clone https://github.com/monoclonalAb/assistant ~/Desktop/projects/assistant
cd ~/Desktop/projects/assistant
cp .env.example .env              # defaults: vault at ~/jarvis-vault, data at ~/.hermes-docker, NZ time
make test                         # ~3 min, throwaway env; expect "74 passed, 0 failed"
make vault-init                   # creates ~/jarvis-vault as a new git repo
make update                       # pull the image, start the gateway
make setup                        # Hermes wizard, see below
make configure                    # Jarvis config + SOUL.md, restarts the gateway
make dream-install                # schedule the nightly consolidation
```

Every command that starts the container runs `make preflight` first. It
refuses to mount anything but a Jarvis vault, so a code project or client repo
can never end up writable by the agent.

In `make setup`:

- **Model: ChatGPT or Codex Subscription.**
  - Do a fresh device-code login here. Don't import `~/.codex/auth.json` from
    your laptop; two machines sharing one login can log each other out.
  - Pick a fast model for chat, since texting latency matters. It shares
    Codex limits with your own Codex use.
- **Messaging → BlueBubbles.**
  - Server URL: `http://host.docker.internal:1234`
  - Password: the BlueBubbles server password
  - Allowed users: your phone number and iCloud address, exactly as iMessage
    shows them
  - Leave the home channel empty and the webhook port unchanged.

### 4. Finish

1. Run `make imessage-check`. Expect "connected to http://host.docker.internal:1234"
   and "webhook registered". Then text Jarvis.
2. **Alerts.** Set `JARVIS_NOTIFY=bluebubbles:+64…` in `.env`, then run
   `make notify-test` and `make dream-reinstall`.
3. **Nightly model.** Run `make model` to see the names. Set
   `JARVIS_DREAM_MODEL` to the strongest one, keep `JARVIS_DREAM_REASONING=high`,
   then run `make dream-reinstall`.
4. **Backup.** Run `gh auth login`, then `make vault-backup-setup`. This:
   - creates the private repo `monoclonalAb/jarvis-vault` and a write deploy
     key used only for it
   - backs up now, then daily at 05:00
5. Tell Jarvis about yourself, run `make dream-run`, and after a couple of
   minutes run `make vault-log`.
6. Run `make check`. It should report 0 problems.

## Day to day

| Command | What it does |
|---------|--------------|
| `make check` | Health and safety audit: access control, nightly job, backups, this Mac |
| `make tui` / `make chat` | Talk to Jarvis from a terminal (e.g. over Tailscale SSH) |
| `make vault-log` | Recent vault history (what Jarvis learned), read safely via the mirror |
| `make dream-run` / `make dream-status` | Run the nightly consolidation now / see jobs and recent runs |
| `make dream-reinstall` | Apply changed `JARVIS_DREAM_*` / `JARVIS_NOTIFY` settings |
| `make vault-backup` | Back up now |
| `make model` | Change the chat model |
| `make imessage-check` / `make notify-test` | iMessage bridge log / send a test alert |
| `make logs` / `make logs-follow` / `make doctor` | Diagnostics |
| `make update` | Pull the latest Hermes image and restart |
| `make test` | End-to-end test in a throwaway environment |

## Security boundary

- **Network.** The container exposes one port, `8645`, bound to `127.0.0.1`
  only, so the local BlueBubbles server can deliver messages. There is no
  Docker socket and no home directory mount.
- **Writable host paths.** Hermes can write exactly two: the vault and its own
  state. The skill and collector script are mounted read-only.
- **Who can reach it.** Anyone who can message Jarvis can steer an agent with a
  shell and network access. The iMessage and Discord allowlists are the gate,
  and `make check` flags anything open (`*_ALLOW_ALL_USERS`, or Discord
  channels/roles without a user list).
- **Don't run git inside `~/jarvis-vault` on the host.** The agent can write its
  `.git/config` and hooks, which git would execute on the host. Instead:
  - read history with `make vault-log`
  - undo a bad night inside the container: `make shell`, then
    `git -C /workspace revert HEAD`
  - backups fetch into a host-owned mirror and push from there, fast-forward
    only, so a compromised agent can't rewrite them

  `make test` plants a booby-trapped `.git` to check that none of it runs.
- **Forgetting** removes information from the current files, not from git
  history (local or backup). Purge history if you need it gone entirely.

## Troubleshooting

- **No replies.**
  - Run `make check` and `make imessage-check`.
  - If the webhook didn't register, make sure BlueBubbles is running.
- **Sends fail with AppleScript `-1743` errors.** The Mac is at the login
  window, or Messages lacks Automation permission.
- **Duplicate replies.** This is a known Hermes BlueBubbles issue
  ([#30708](https://github.com/NousResearch/hermes-agent/issues/30708)).
- **Jarvis doesn't seem to know its profile.** Run `make check`, which verifies
  that sessions start in the vault. Text `/new` for a fresh session.
- **Nightly job failed.** Run `make dream-status`. The watermark only advances
  after a successful commit, so the next run retries the same messages.
- **Backup failed with "couldn't fast-forward".** The vault's history was
  rewritten. Find out why before forcing anything.
- **`hermes send -t bluebubbles:…` fails with "address already in use".** That's
  a Hermes limitation while the gateway runs. Use `scripts/notify.sh`, which is
  what the alerts use.
