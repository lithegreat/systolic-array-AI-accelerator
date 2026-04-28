---
name: glab-cli
user-invocable: true
description: 'Quick reference skill for using the GitLab CLI (glab) with the project host gitlab.lrz.de.'
---

# glab CLI — Quick Skill

Use this skill when you need to authenticate, query issues/MRs, or script common GitLab tasks from the command line for this repository.

## Authenticate
- OAuth client (preferred if org provides client_id):
  - `glab config set client_id <CLIENT_ID> -g --host gitlab.lrz.de`
  - `glab auth login --hostname gitlab.lrz.de`
- Personal Access Token (PAT):
  - `glab auth login --hostname gitlab.lrz.de` (choose "Paste token")
  - or: `echo "<PAT>" | glab auth login --stdin --hostname gitlab.lrz.de`

## Common Commands
- Show git remotes: `git remote -v`
- Check auth: `glab auth status`
- Show repo info: `glab repo view` or `glab repo view -R OWNER/REPO`
- List issues: `glab issue list -A -R OWNER/REPO -P 100 -O json`
- View a single issue: `glab issue view <IID> -R OWNER/REPO`
- Create MR from current branch: `glab mr create -R OWNER/REPO`

## Notes & Tips
- When remotes use a different SSH hostname than the API host, pass `-R` with the repo path or set `hosts.<host>.ssh_host` in your glab config.
- Prefer machine-readable output for scripting (`-O json`) and use `-R OWNER/REPO` to avoid host-resolution ambiguity.
- Use `glab config edit` to inspect or set per-host config entries (e.g., `api_host`, `client_id`, `token`).

## When To Use This Skill
- Use this skill for repository administration tasks (issues, MRs, releases), CI troubleshooting, and automation scripts where GitLab API access is needed from the developer workstation or CI runner.

---
Built for the `ai-pro-msmcd-labs/2025/os/group5` project.
