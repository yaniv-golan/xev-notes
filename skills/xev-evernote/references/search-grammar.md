# Evernote Search Grammar

xev-cli search queries use Evernote's search grammar. All queries are passed directly to the Evernote API.

## Basic Search

| Query | Matches |
|-------|---------|
| `meeting notes` | Notes containing both "meeting" AND "notes" |
| `"quarterly review"` | Notes containing the exact phrase |
| `any: cat dog bird` | Notes containing ANY of the words |

## Field Searches

| Syntax | Matches |
|--------|---------|
| `intitle:planning` | "planning" appears in the note title |
| `notebook:Private` | Notes in the "Private" notebook |
| `tag:important` | Notes with the "important" tag |
| `-tag:archive` | Notes WITHOUT the "archive" tag |
| `source:web.clip` | Notes created by web clipper |

## Date Filters

| Syntax | Matches |
|--------|---------|
| `created:day-7` | Created in the last 7 days |
| `created:day-30` | Created in the last 30 days |
| `updated:day-1` | Updated today |
| `updated:day-7` | Updated in the last week |
| `created:20260101` | Created on or after January 1, 2026 |
| `created:20260101 -created:20260201` | Created in January 2026 |

## Content Filters

| Syntax | Matches |
|--------|---------|
| `todo:true` | Notes with checked checkboxes |
| `todo:false` | Notes with unchecked checkboxes |
| `encryption:` | Notes with encrypted content |
| `resource:image/*` | Notes with image attachments |
| `resource:application/pdf` | Notes with PDF attachments |

## Combining Filters

Filters combine with AND by default:

```
notebook:Work intitle:meeting updated:day-30
```

This finds notes in the "Work" notebook with "meeting" in the title, updated in the last 30 days.

## Tips

- Use `--notebook` flag instead of `notebook:` for cleaner syntax: `xev-cli search "Q4" --notebook "Work"`
- Wildcard `*` matches all notes (use with `--limit` to avoid timeouts)
- Notebook names with spaces need quotes: `notebook:"My Notebook"`
