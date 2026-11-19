# Claude Code status line — build prompt

This spec describes what `statusline.py` does. Paste it into Claude Code to
rebuild the status line from scratch. Update it whenever the script changes.

---

Create a two-row Claude Code status line as a Python 3 script at
`~/.claude/statusline.py` (make it executable). Use only the standard library:
no jq, no bash, no third-party packages. Register it in `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/statusline.py",
  "padding": 0,
  "refreshInterval": 60
}
```

The script reads Claude Code's status JSON from stdin and prints two lines.
Use 256-color ANSI codes (`\033[38;5;<n>m`) and reset after every field.

## Row 1 — fields joined by a grey (245) ` · ` separator

1. **Username** (orange, 214): the logged-in OS user from `getpass.getuser()`.
   If it can't be read, leave the field out.
2. **Folder** (cyan, 51): the last path part of `workspace.current_dir`, or `?`.
3. **Model** (bright white, 231): `model.display_name`, shown only if present.
4. **Tokens** (light blue, 111): `<total_input_tokens> / <context_window_size>`
   from `context_window`, written compactly (`1.2k`, `3.4M`, trailing `.0` removed).
   Shown only if `context_window_size` is present.
5. **Thinking**: `thinking on` in green (49) or `thinking off` in grey (245),
   from `thinking.enabled`.
6. **Effort**: `effort <level>` from `effort.level`, with `medium` written as `med`.
   Colors: max = 196, xhigh = 201, high = 226, med = 49, low and anything else = grey 245.

## Row 2 — meters joined by a grey `  ·  ` separator

Each meter is 10 dots (`●` filled, `○` empty in dim grey 240) followed by a
percentage right-aligned to 3 characters. Filled dots = ceil(pct/100 × 10),
with at least 1 dot when pct > 0 and at most 9 dots when pct < 100.

- **ctx**: grey label `ctx`. Scale it to a working budget of **600,000 input
  tokens = 100%**, not to the model's full context window; cap it at 100%.
  If `total_input_tokens` is missing or 0, use
  `context_window.used_percentage / 100 × context_window_size` instead.
  Color each dot by its position, green to red:
  `[46, 82, 118, 154, 190, 226, 220, 214, 208, 196]`.
- **5h** and **7d**: from `rate_limits.five_hour` and `rate_limits.seven_day`,
  shown only when `used_percentage` is present. Use one color for the whole bar,
  chosen by **projected overshoot risk** rather than by the raw percentage:
  - Window lengths: 5h = 18,000 s, 7d = 604,800 s.
    remaining = clamp(resets_at − now, 0, window);
    elapsed = window − remaining.
  - used ≥ 100 → red (196). elapsed < 60 s or used ≤ 0 → green (49).
  - risk = (used / elapsed × remaining) / (100 − used):
    under 0.85 → green, under 1.15 → yellow (226), otherwise → red.
  - If there is no `resets_at`, use raw thresholds instead:
    under 70 → green, under 90 → yellow, otherwise → red.
  - After the percentage, add the time until reset in grey:
    `↻<h>h<mm>m`, or `↻<m>m` when under an hour.

## Robustness

- Treat bad or empty stdin as `{}`. Read nested keys with a safe getter that
  returns a default instead of raising.
- If anything fails while building the rows, print this fallback and still exit 0:
  a cyan `?` on row 1, and a grey `ctx` label with an empty bar and `  0%` on row 2.
- Always exit with status 0.

Example output:

```
cyburdine · mnslab.io · Opus 5 (1M context) · 214.3k / 1M · thinking on · effort med
ctx ●●●●○○○○○○  36%  ·  5h ●●●●●○○○○○  47% ↻2h09m  ·  7d ●●●●●●●○○○  63% ↻62h09m
```
