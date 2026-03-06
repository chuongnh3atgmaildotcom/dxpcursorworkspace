# Workspace agent instructions

All agent guidance lives under **`_workspace`**, which is outside the sub-repositories. Nothing in sub-repos is changed; agent plans, rules, and IDE metadata are only in _workspace.

## Flow and architecture

- **ARCHITECTURE.md** — Multi-repo job/API flow, C4 maps, and which repo does what. Use it when tracing requests or changing cross-repo contracts.

## Per-repo agent docs

Per-repo AGENTS.md copies live under **docs/agents/**:

- **docs/agents/dxc-deployment-automation-AGENTS.md** — PowerShell modules, runbooks, build scripts (dxc-deployment-automation)
- **docs/agents/PaaS-AGENTS.md** — PaaS Portal monorepo (.NET, workers, UI)

See **docs/agents/README.md** for the list and how to add or update repo docs.

## Rules and IDE metadata

- **.cursor/rules/** — Workspace rules (multi-repo flow, citation format, incremental reasoning, etc.). All of this lives in _workspace only.
