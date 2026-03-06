# Per-repo agent instructions (workspace)

Agent guidance for each repository is kept here in **`_workspace`**, which is outside all sub-repos. Agent plans, rules, and IDE metadata live only in _workspace; sub-repos are not modified.

| Repo | Doc |
|------|-----|
| dxc-deployment-automation | [dxc-deployment-automation-AGENTS.md](dxc-deployment-automation-AGENTS.md) |
| PaaS | [PaaS-AGENTS.md](PaaS-AGENTS.md) |

When adding a new repo that has an `AGENTS.md`, copy it into this folder as `{repo-name}-AGENTS.md` and add a row above. Keep the workspace copy in sync when the source repo’s AGENTS.md changes.

**Workspace-level flow and rules:** See `_workspace/ARCHITECTURE.md` and `_workspace/.cursor/rules/`.
