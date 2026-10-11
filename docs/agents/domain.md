# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`GLOSSARY-MAP.md`** at the repo root: this repo is multi-context — the map points at one `GLOSSARY.md` per context under `lib/<主模块>/`. Read each one relevant to the topic.
- **`docs/adr/`** for system-wide decisions, and **`lib/<主模块>/docs/adr/`** for context-scoped decisions. ADR numbers are globally unique across both, so `ADR-NNNN` resolves from anywhere.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

```
/
├── GLOSSARY-MAP.md                       ← 上下文地图：有哪几个上下文、各自住哪、彼此什么关系
├── docs/adr/                            ← 系统级决策，根部连排
└── lib/
    ├── player/                          ← 一个上下文的主模块
    │   ├── GLOSSARY.md
    │   └── docs/adr/                    ← 该上下文的决策，编号与系统级连排
    ├── annotation/
    │   ├── GLOSSARY.md
    │   └── docs/adr/
    └── …
```

一个上下文的主模块是它词表与决策的落点；该上下文还覆盖哪些模块，由 `GLOSSARY-MAP.md` 逐条写明（例如「节拍」的呈现与发声件住 `lib/player`，纯值件住 `lib/core`）。

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in that concept's context `GLOSSARY.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0001 (media_kit as the player core), but worth reopening because…_
