#!/usr/bin/env python3
"""Pre-run script for the nightly `jarvis-dream` cron job.

Hermes runs this before the job and injects its stdout into the job prompt, so
the dreaming agent starts with everything it needs:

  WINDOW       time range covered + the exact command that advances the watermark
  INBOX        items the chat agent flagged in /workspace/inbox.md
  TRANSCRIPT   every user/assistant message since the last successful dream
  VAULT INDEX  every entity file with its type, name and aliases

This script only reads. The agent writes /workspace/.dream/watermark as part of
its final commit, so a failed run is retried with the same window next time.
When there is nothing new it prints {"wakeAgent": false} and Hermes skips the
LLM call entirely.

Mounted read-only into the container at /opt/data/scripts/ by compose.yaml.
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None  # type: ignore[assignment]

VAULT = Path(os.environ.get("JARVIS_VAULT", "/workspace"))
HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/opt/data"))
DB_PATH = HERMES_HOME / "state.db"
WATERMARK = VAULT / ".dream" / "watermark"

FIRST_RUN_LOOKBACK_S = 7 * 24 * 3600  # first dream looks back a week
MAX_TRANSCRIPT_CHARS = int(os.environ.get("JARVIS_DREAM_MAX_CHARS", "150000"))
MAX_USER_MSG_CHARS = 4000
MAX_ASSISTANT_MSG_CHARS = 1200
MAX_INDEX_LINES = 400
EXCLUDED_SOURCES = ("cron",)  # the dream job's own sessions, reminders, etc.
INDEX_SKIP_DIRS = {".git", ".dream", "bin", "system", "timeline"}
HERMES_INSTALL = Path("/opt/hermes")
WITHHELD = "[withheld: matched Hermes's prompt-injection filter]"
INDEX_SKIP_FILES = {"README.md", "profile.md", "now.md", "tasks.md", "inbox.md"}


def local_tz():
    name = os.environ.get("HERMES_TIMEZONE") or os.environ.get("TZ")
    if name and ZoneInfo is not None:
        try:
            return ZoneInfo(name)
        except Exception:
            pass
    return datetime.now().astimezone().tzinfo


TZ = local_tz()


def fmt_ts(ts: float, pattern: str = "%Y-%m-%d %H:%M") -> str:
    return datetime.fromtimestamp(ts, TZ).strftime(pattern)


def read_watermark() -> float | None:
    try:
        return float(WATERMARK.read_text().strip())
    except (FileNotFoundError, ValueError):
        return None


def text_of(content: str | None) -> str:
    """Messages store plain text, or JSON-encoded multimodal parts."""
    if not content:
        return ""
    stripped = content.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        try:
            parts = json.loads(stripped)
        except json.JSONDecodeError:
            return stripped
        if isinstance(parts, list):
            out = []
            for part in parts:
                if isinstance(part, dict):
                    if part.get("type") == "text" and part.get("text"):
                        out.append(str(part["text"]))
                    elif part.get("type"):
                        out.append(f"[{part['type']}]")
                elif isinstance(part, str):
                    out.append(part)
            return "\n".join(out).strip()
    return stripped


def clip(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[:limit].rstrip() + " …[clipped]"


def fetch_messages(since: float, until: float) -> list[sqlite3.Row]:
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True, timeout=10)
    conn.row_factory = sqlite3.Row
    try:
        cols = {r["name"] for r in conn.execute("PRAGMA table_info(messages)")}
        summary_filter = "AND COALESCE(m._compressed_summary, 0) = 0" if "_compressed_summary" in cols else ""
        placeholders = ",".join("?" for _ in EXCLUDED_SOURCES)
        return conn.execute(
            f"""
            SELECT m.id, m.session_id, m.role, m.content, m.timestamp,
                   s.source, s.title, s.display_name
            FROM messages m JOIN sessions s ON s.id = m.session_id
            WHERE m.timestamp > ? AND m.timestamp <= ?
              AND m.role IN ('user', 'assistant')
              AND m.content IS NOT NULL AND TRIM(m.content) != ''
              AND s.source NOT IN ({placeholders})
              {summary_filter}
            ORDER BY m.timestamp, m.id
            """,
            (since, until, *EXCLUDED_SOURCES),
        ).fetchall()
    finally:
        conn.close()


def build_transcript(rows: list[sqlite3.Row], until: float) -> tuple[str, int, float, bool]:
    """Return (text, message_count, effective_window_end, partial)."""
    seen: set[tuple[str, str, int]] = set()
    lines: list[str] = []
    used = 0
    count = 0
    current_session = None
    current_day = None
    window_end = until
    partial = False

    for i, row in enumerate(rows):
        body = text_of(row["content"])
        if not body:
            continue
        key = (row["role"], body, int(row["timestamp"]))
        if key in seen:  # compaction can copy messages into a child session
            continue
        seen.add(key)

        chunk: list[str] = []
        if row["session_id"] != current_session:
            label = row["title"] or row["display_name"] or "untitled"
            chunk.append(f"\n### {row['source']} · {label} · session {row['session_id'][:8]}")
            current_session = row["session_id"]
            current_day = None
        day = fmt_ts(row["timestamp"], "%A %Y-%m-%d")
        if day != current_day:
            chunk.append(f"-- {day} --")
            current_day = day
        who = "Eric" if row["role"] == "user" else "Jarvis"
        limit = MAX_USER_MSG_CHARS if row["role"] == "user" else MAX_ASSISTANT_MSG_CHARS
        chunk.append(f"[{fmt_ts(row['timestamp'], '%H:%M')}] {who}: {clip(body, limit)}")

        piece = "\n".join(chunk)
        if used + len(piece) > MAX_TRANSCRIPT_CHARS and count > 0:
            # Stop just before this message so the next run starts with it.
            window_end = min(rows[i - 1]["timestamp"], row["timestamp"] - 1e-6)
            partial = True
            break
        lines.append(piece)
        used += len(piece) + 1
        count += 1

    return "\n".join(lines).strip(), count, window_end, partial


def read_inbox() -> list[str]:
    path = VAULT / "inbox.md"
    if not path.exists():
        return []
    return [ln.rstrip() for ln in path.read_text(encoding="utf-8").splitlines() if ln.startswith("- ")]


FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n", re.S)


def frontmatter(path: Path) -> dict[str, str]:
    try:
        head = path.read_text(encoding="utf-8")[:2000]
    except (OSError, UnicodeDecodeError):
        return {}
    match = FRONTMATTER_RE.match(head)
    if not match:
        return {}
    fields = {}
    for line in match.group(1).splitlines():
        if ":" in line and not line.startswith(" "):
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()
    return fields


def vault_index() -> list[str]:
    entries = []
    for path in sorted(VAULT.rglob("*.md")):
        rel = path.relative_to(VAULT)
        if rel.parts[0] in INDEX_SKIP_DIRS or rel.name.startswith(".") or str(rel) in INDEX_SKIP_FILES:
            continue
        fm = frontmatter(path)
        entries.append(
            f"[[{rel.with_suffix('')}]] | {fm.get('type', '?')} | {fm.get('name', '')} | aliases: {fm.get('aliases', '[]')}"
        )
    if len(entries) > MAX_INDEX_LINES:
        extra = len(entries) - MAX_INDEX_LINES
        entries = entries[:MAX_INDEX_LINES] + [f"… {extra} more files (use rg to search)"]
    return entries


def legacy_memories() -> str:
    """On the first run only, hand over anything in Hermes's built-in memory files."""
    out = []
    for name in ("USER.md", "MEMORY.md"):
        path = HERMES_HOME / "memories" / name
        if path.exists() and path.read_text(encoding="utf-8").strip():
            out.append(f"--- {name} ---\n{path.read_text(encoding='utf-8').strip()}")
    return "\n\n".join(out)


def load_scanner():
    """Hermes's filter for assembled cron prompts (skills + injected data).

    Hermes scans this script's output as part of the job prompt. One matching
    line (say Eric texted a jailbreak meme, or pasted a suspicious email) would
    block the whole nightly job, and because the watermark only advances on
    success, it would be blocked again every night. So matching lines are
    withheld here instead. Returns None outside the Hermes container.
    """
    if not HERMES_INSTALL.is_dir():
        return None
    sys.path.insert(0, str(HERMES_INSTALL))
    try:
        from tools.cronjob_prompt_scan import _scan_cron_skill_assembled
    except Exception:
        return None
    return lambda text: bool(_scan_cron_skill_assembled(text)[1])


PREFIX_RE = re.compile(r"^(\[\d\d:\d\d\] \w+: |- )")


def withhold(line: str) -> str:
    match = PREFIX_RE.match(line)
    return (match.group(1) if match else "") + WITHHELD


def sanitize(text: str, scan) -> tuple[str, int]:
    """Withhold every line (or pair of lines) the scanner flags. Returns (text, count)."""
    if scan is None or not scan(text):
        return text, 0
    lines = text.split("\n")
    count = 0
    for i, line in enumerate(lines):
        if WITHHELD not in line and scan(line):
            lines[i] = withhold(line)
            count += 1
    if scan("\n".join(lines)):  # a match can straddle a line break
        for i in range(len(lines) - 1):
            if scan(lines[i] + "\n" + lines[i + 1]):
                for j in (i, i + 1):
                    if WITHHELD not in lines[j]:
                        lines[j] = withhold(lines[j])
                        count += 1
    return "\n".join(lines), count


def main() -> int:
    if not (VAULT / ".git").exists():
        print(f"ERROR: {VAULT} is not an initialised vault (no .git). Run `make vault-init` on the host.")
        return 1
    if not DB_PATH.exists():
        print(f"ERROR: session database not found at {DB_PATH}.")
        return 1

    until = time.time()
    watermark = read_watermark()
    first_run = watermark is None
    since = watermark if watermark is not None else until - FIRST_RUN_LOOKBACK_S

    rows = fetch_messages(since, until)
    transcript, count, window_end, partial = build_transcript(rows, until)
    inbox = read_inbox()
    legacy = legacy_memories() if first_run else ""

    if count == 0 and not inbox and not legacy:
        print(f"Nothing new since {fmt_ts(since)}.")
        print(json.dumps({"wakeAgent": False}))
        return 0

    out = [
        "== WINDOW ==",
        f"From {fmt_ts(since)} to {fmt_ts(window_end)} ({TZ}). Today is {fmt_ts(until, '%A %Y-%m-%d')}.",
        f"{count} messages. {'FIRST RUN — no watermark yet.' if first_run else ''}".strip(),
    ]
    if partial:
        out.append("PARTIAL: the transcript hit the size cap; later messages will be processed on the next run.")
    out += [
        "When everything is written, advance the watermark with exactly:",
        # repr() round-trips the float exactly; rounding could re-include or skip a message.
        f"  echo {window_end!r} > /workspace/.dream/watermark",
        "",
        "== INBOX ==",
        "\n".join(inbox) if inbox else "(empty)",
    ]
    if legacy:
        out += ["", "== LEGACY HERMES MEMORY (import once into the vault) ==", legacy]
    out += [
        "",
        "== TRANSCRIPT ==",
        transcript or "(no messages)",
        "",
        "== VAULT INDEX ==",
        "\n".join(vault_index()) or "(no entity files yet)",
    ]
    scan = load_scanner()
    text, withheld = sanitize("\n".join(out), scan)
    if scan is not None and scan(text):
        # Couldn't isolate the match to a line or two: hand over only the window,
        # so the job still runs and advances past these messages.
        window = out[: out.index("== INBOX ==")]
        text = "\n".join(window + [
            "== TRANSCRIPT ==",
            "(all content withheld: Hermes's prompt-injection filter matched text that couldn't be",
            "isolated. Write nothing; just advance the watermark and commit.)",
        ])
    elif withheld:
        text += f"\n\n({withheld} line(s) withheld by Hermes's prompt-injection filter.)"
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
