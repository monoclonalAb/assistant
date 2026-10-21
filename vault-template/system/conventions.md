# Vault conventions

Everything here is plain markdown in git. Retrieval is keyword search (`rg`), so
file names, `aliases` and consistent wording are what make memory findable.

## Entity files

One file per person, organisation, project, place or cluster of preferences.

| folder      | type    | what goes here |
|-------------|---------|----------------|
| `people/`   | person  | anyone Eric mentions more than in passing (Eric himself is `people/eric`) |
| `orgs/`     | org     | employers, universities, clubs, companies and services he deals with |
| `projects/` | project | ongoing efforts with a goal: side projects, trips being planned, a job hunt |
| `places/`   | place   | homes, regular venues, cities that matter |
| `prefs/`    | pref    | preference clusters: food, travel, tech, shopping, communication… |

**The path is the ID.** `people/alanna-zheng.md` has ID `people/alanna-zheng`;
link to it as `[[people/alanna-zheng]]`. File names are lowercase kebab-case,
using the full name where known.

```markdown
---
type: person
name: Alanna Zheng
aliases: [Alanna, Lan, my sister, Alanna Z]
updated: 2026-09-27
---
# Alanna Zheng

Eric's younger sister; studies design at Victoria.

## Facts
- 2026-09-20: Birthday is 14 March.
- 2026-09-27: Lives in Wellington (corrected; was noted as Auckland).
- 2026-09-27: Loves matcha; Eric often gets her matcha things as gifts.

## Related
- [[people/eric]]: brother
- [[orgs/victoria-university]]: studies there
```

Rules:

- `aliases` holds every way Eric refers to the thing: nicknames, relationships
  ("my sister", "mum", "my manager"), abbreviations, likely misspellings.
- A one-line summary under the title says what this is and why it matters.
- Facts are atomic bullets starting with the date learned (`YYYY-MM-DD:`), in
  Eric's terms.
- Corrections replace the old fact in place and keep the trail, e.g.
  `(corrected; was noted as Auckland)`.
- Temporary details (this week's plans, one-off events) go in the day's timeline
  note and `now.md`, not in entity files, unless they change something lasting.
- When the same kind of detail keeps appearing, generalise it into a trait
  ("prefers aisle seats" instead of three flight anecdotes).
- `updated` is the date of the last content change.
- Uncertain facts get `(unconfirmed)`.

## Timeline

`timeline/YYYY/YYYY-MM-DD.md`, one per day with meaningful conversation:

```markdown
---
type: day
date: 2026-09-27
---
# Saturday 27 September 2026
- Planned Alanna's birthday dinner with [[people/alanna-zheng]]; booked [[places/amisfield]] for 7pm on 14 March.
- Stressed about the [[projects/beacon]] launch; wants reminders to take breaks.
```

## profile.md (under 8,000 characters)

The part of memory that's always in context. Only durable information.

1. `## Life context`: who Eric is, work and study, where he lives, the people
   who matter (linked), the big ongoing threads.
2. `## Autonomy calibration`: when to act and when to ask; explicit
   permissions and prohibitions he's given.
3. `## Communication style`: tone, length, formatting, quiet hours, pet
   peeves, and things he's corrected about how Jarvis talks.
4. `## Index`: one line per important file, e.g.
   `[[people/alanna-zheng]]: sister (Lan)`.

## now.md (under 3,000 characters)

1. `## This week`: what Eric is in the middle of, dated things coming up in the
   next 14 days, and open loops he's waiting on.
2. `## Recent days`: 1–2 lines per day for the last 7 days, newest first,
   linking the timeline notes.

## tasks.md

Sections `## Now`, `## Next`, `## Waiting`, `## Done`. Items look like
`- [ ] book dentist (due 2026-10-02): context`. Done items look like
`- [x] … (done 2026-09-27)`. Done items older than 7 days are removed.

## inbox.md

Written by the chat agent during the day as one dated line per item, and
emptied by the nightly job.
