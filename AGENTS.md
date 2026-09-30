## Agent skills

### Issue tracker

Issues are tracked as GitHub issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles map 1:1 to label strings: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Multi-context layout: `CONTEXT-MAP.md` at the repo root points at one `CONTEXT.md` per context under `lib/<主模块>/`; ADRs are numbered globally, system-wide ones in `docs/adr/`, context-scoped ones in `lib/<主模块>/docs/adr/`. See `docs/agents/domain.md`.
