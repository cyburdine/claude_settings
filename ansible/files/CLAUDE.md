# Personal coding preferences

## My stack
- I work almost entirely on macOS / Apple Silicon. Assume Homebrew; prefer native-Mac solutions.
- Languages, by frequency: Python (desktop apps), TypeScript/JavaScript (React, Remotion,
  Cloudflare Workers, Node/Express), Swift/SwiftUI (macOS apps), Jekyll for my site.

## Tooling
- JS/TS: use **npm** — every project uses package-lock.json. Don't switch a project to pnpm/yarn.
- Python: venv + requirements.txt for simple apps; pyproject.toml + setuptools for packages;
  py2app to bundle Mac apps. No poetry/uv.
- Pin exact dependency versions (numpy==2.4.6), not ranges. Ask before adding a new dependency.
- Use ripgrep (rg) for searching, not grep.

## Code style
- Indentation: 2 spaces in JS/TS, 4 spaces in Python and Swift.
- Python: annotate function signatures; `from __future__ import annotations`; modern generics
  (list[str], Path | None); Google-style docstrings. snake_case funcs, PascalCase classes,
  UPPER_SNAKE constants, leading-underscore privates.
- TypeScript: keep strict: true; type the public surface.
- Exports: named for utilities/modules; default is expected for React components, Next.js pages,
  and Worker handlers — don't force named exports on those.
- Swift: final class for services/view-models, struct for models, explicit access control
  (private, private(set)), // MARK: section markers.

## Workflow
- Make minimal, targeted changes. Don't refactor unrelated code.
- If a project has tests (pytest/vitest), run them before suggesting a commit. Many of my
  smaller apps have none — don't invent a suite, just tell me.
- If a project is typed (TS strict / annotated Python), run the type checker after changes.

## Project docs
- I keep a detailed CLAUDE.md per non-trivial project: what it is, architecture, and a
  "what I tried that failed — don't retry" section. When you learn something the hard way,
  add it there.

## Communication
- When a task has multiple valid approaches, list the tradeoffs before picking one.
- Be concrete and specific over generic.
