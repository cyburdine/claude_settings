# claude-config-ansible

Deploys your Claude Code customizations to every instance you run — this Mac and
your Rocky Linux servers — by writing into `~/.claude/` on each host.

## What it installs

| Target (`~/.claude/`) | Source | Notes |
| --- | --- | --- |
| `CLAUDE.md` | `files/CLAUDE.md` | Personal user memory, read in every session. |
| `rules/*.md` | `files/rules/` | Modular + path-scoped rules. |
| `settings.json` | `group_vars/all.yml` (`managed_settings`) | **Merged** into any existing file. |

`settings.json` covers the toolchain-agnostic items from your notes: the
`$schema` line, permission allow/ask/deny lists, sensitive-file read denies,
bash sandboxing, `effortLevel`, `autoUpdatesChannel`, `tui`, and the empty
`attribution` block (drops the co-author byline). The npm/prettier examples
from the notes are intentionally left out.

## Setup

1. Install Ansible on the control machine (this Mac):
   ```bash
   brew install ansible
   ```
2. Edit `inventory.ini` — uncomment and fill in your Rocky Linux hosts under
   `[rocky_servers]`. Make sure key-based SSH works to each one.

## Run

```bash
cd claude-config-ansible

ansible-playbook playbook.yml --check --diff   # dry run, shows every change
ansible-playbook playbook.yml                  # apply to all hosts
ansible-playbook playbook.yml --limit mac-local
ansible-playbook playbook.yml --limit rocky_servers
```

## How it's safe

- **Non-destructive `settings.json`.** The playbook reads any existing file,
  deep-merges the managed keys into it, and **unions** the permission lists, so
  your existing keys and allow/deny entries are preserved.
- **Backups.** Every file it changes is backed up first (Ansible writes a
  timestamped sibling), so a bad run is always recoverable.
- **Idempotent.** Re-running makes no changes once a host already matches.

## Customizing

- Change what lands in `settings.json` everywhere → edit `managed_settings` in
  `group_vars/all.yml`.
- Change memory/rules → edit `files/CLAUDE.md` and `files/rules/*.md`.

## Caveats worth knowing

- A couple of fields in these notes (e.g. `effortLevel`, `autoUpdatesChannel`,
  `tui`, `sandbox`) may lag or lead your installed CLI version. The published
  JSON schema can warn on brand-new fields even when they're valid — and unknown
  fields are simply ignored by the CLI, so they won't break anything.
- This only manages the **user scope** (`~/.claude/`). Project-scoped pieces
  (per-repo `.claude/settings.json` for sensitive-file denies, project rules)
  belong in each repo and aren't deployed here.
