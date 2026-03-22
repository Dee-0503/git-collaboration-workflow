---
name: setup-project
description: Configure Git Collaboration Workflow plugin for this project. Auto-invoked on first session when .claude/git-collab.yml is missing. Presents mode selection (full/minimal/disabled) and optionally initializes git repo.
model: haiku
---

# Setup Project — Git Collaboration Workflow

This skill configures the plugin for the current project. It is auto-invoked by the SessionStart hook when `.claude/git-collab.yml` is not found.

## Step 1: Detect environment

Check if the current directory is a git repository:
```bash
git rev-parse --git-dir > /dev/null 2>&1 && echo "GIT_REPO" || echo "NOT_GIT"
```

## Step 2: Present mode selection

Use **AskUserQuestion** to show a selection panel.

**If NOT a git repo**, present these options:
- **初始化 Git + full** — Run `git init` and enable all hooks (recommended for new projects)
- **初始化 Git + minimal** — Run `git init`, only keep secret scanning and conflict marker detection
- **disabled** — Do not initialize Git, disable the plugin entirely

**If already a git repo**, present these options:
- **full** — All hooks active (recommended for team collaboration)
- **minimal** — Only secret scanning and conflict marker detection
- **disabled** — Disable the plugin entirely

## Step 3: Execute choice

Based on the user's selection:

1. If git init is needed, run:
```bash
git init
```

2. Create the config file:
```bash
mkdir -p .claude
echo "mode: <chosen_mode>" > .claude/git-collab.yml
```

3. Confirm to the user:
> ✅ Git Collaboration Workflow configured: mode set to `<chosen_mode>`. This config is saved in `.claude/git-collab.yml` — you can change it anytime by editing this file.
