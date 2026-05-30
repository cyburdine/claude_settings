# claude_settings

My Current Claude Statusline, feel free to point claude at the file statusline.sh and it will replicate below:

<img width="1760" height="112" alt="image" src="https://github.com/user-attachments/assets/a3b78e80-6732-476d-94fb-cc72cf229881" />

How to Implement: 
Simply go into Claude Code in a linux termal and type the following prompt: 

"update your statusline using this script: https://raw.githubusercontent.com/cyburdine/claude_settings/refs/heads/main/statusline.sh"

let it spin for a bit and it should update.  On a few systems I've had to close claude and open it back up to show the statusline so if you don't see it automatically update try that.

If you end up adding some cool features, definitely reach out! I'd love to see what others are doing with this.

---

## Deploying settings to every machine with Ansible (`ansible/`)

The statusline above is one file. If you run Claude Code on more than one box
(say a Mac plus a few Linux servers), the `ansible/` folder pushes a whole set
of customizations to **every instance at once** — into `~/.claude/` on each host.

### What it installs

| Target (`~/.claude/`) | Source | Notes |
| --- | --- | --- |
| `CLAUDE.md` | `ansible/files/CLAUDE.md` | Personal user memory, read every session. |
| `rules/*.md` | `ansible/files/rules/` | Modular + path-scoped rules. |
| `settings.json` | `ansible/group_vars/all.yml` (`managed_settings`) | **Merged**, not overwritten. |

`settings.json` covers the toolchain-agnostic pieces: the `$schema` line,
permission allow/ask/deny lists, sensitive-file read denies, bash sandboxing,
`effortLevel`, `autoUpdatesChannel`, `tui`, and an empty `attribution` block
(drops the co-author byline).

### How to use it

```bash
# 1. Install Ansible on the machine you'll run from (e.g. your Mac)
brew install ansible          # macOS
# sudo dnf install ansible     # Rocky / RHEL

cd ansible

# 2. Add your hosts. Edit inventory.ini and uncomment/fill in the
#    [rocky_servers] block with each server's host/IP and SSH user.
#    The "mac-local" host already targets the machine you run from (no SSH).

# 3. Preview the changes without writing anything
ansible-playbook playbook.yml --check --diff

# 4. Apply
ansible-playbook playbook.yml                  # all hosts
ansible-playbook playbook.yml --limit mac-local
ansible-playbook playbook.yml --limit rocky_servers
```

### Why it's safe to run on machines you've already configured

- **Non-destructive `settings.json`.** It reads any existing file, deep-merges
  the managed keys, and **unions** the permission lists — your existing keys and
  allow/deny entries are kept, not clobbered.
- **Backups.** Every file it changes is backed up first (a timestamped sibling).
- **Idempotent.** Re-running makes no changes once a host already matches.

Customize what gets deployed by editing `ansible/group_vars/all.yml`
(settings) and `ansible/files/` (memory + rules). Full details and caveats live
in [`ansible/README.md`](ansible/README.md).
