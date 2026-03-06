# PaaS — Agent instructions (workspace copy)

**Source repo:** `PaaS`. This copy lives in the workspace so agent/rules/IDE metadata are not tracked in sub-repositories.

---

# AI Assistant Instructions for This Repository

Purpose: Help AI agents contribute safely and productively to the Optimizely PaaS Portal monorepo. Keep answers specific to THIS codebase—prefer pointing to concrete files/scripts over generic .NET advice.

## Architecture Snapshot
- Solution: `PaaS/PaaS.sln` aggregates Portal UI, domain/application layers, provisioning workers, infra mgmt libraries, test/spec projects.
- Core layering:
  - `EPiServer.PaaS.Core/`: Shared domain abstractions + Mongo-backed core models.
  - `EPiServer.PaaS.Application/`: Application services (email templates, hostname/location/plan logic) targeting `netstandard2.0` and referencing Core + Infrastructure.Common + Messages.
  - `EPiServer.PaaS.DataAccess/`: Persistence helpers & services (Mongo setup, repository-like utilities) separated from pure domain (`Core`). Keep database-specific concerns here rather than in domain.
  - `EPiServer.PaaS.Migrations/`: Data / schema migration utilities; pair related specs in `EPiServer.PaaS.Migrations.Specs/`. For integration DB harness pieces see `EPiServer.PaaS.Database.Integration.Base/`.
  - `EPiServer.PaaS.Infrastructure.*`: Technology/provider adapters. Avoid leaking provider SDK types upward—wrap them.
    - Cloud providers: `AzureManagement`, `AwsManagement`, `CloudFlareManagement`
    - Monitoring/Observability: `Datadog`, `PingdomManagement`, `ApplicationLogging`, `Logging`
    - External services: `ActiveDirectory`, `SendGrid`, `Mail`, `Runbooks`, `Turnstile`
    - Platform services: `ServiceBus` (Base, Sending), `SqlManagement`, `DnsLookup`, `EpiLicenseManagement`, `FindManagement`, `OrderManagement`
    - Cross-cutting: `Configuration`, `Common` (shared abstractions)
    - Testing: `Mocks`, `MockWorkers` (test doubles for infrastructure dependencies)
  - `EPiServer.PaaS.Portal`: Web UI (legacy MVC + SignalR). Static assets & legacy bundles under `ClientResources/`; build tooling uses `gulpfile.js` & `webpack.config.js`.
  - `EPiServer.PaaS.Services.Portal`: Service host layer for portal-related background hosted services (separate from MVC site).
  - Aspire hosting defaults: `EPiserver.PaaS.Aspire.AppHost/` & `EPiserver.PaaS.Aspire.ServiceDefaults/` supply shared service configuration (`AddServiceDefaults`, instrumentation, health) consumed by worker/service hosts.
  - Workers / background processes: look for projects ending in `Worker` or `.Base`. `.Base` projects (e.g. `ProvisioningWorker.Base`) hold reusable logic + embedded templates; `Services.<Name>Worker` adds hosting/instrumentation.
    - Current workers: `ProvisioningWorker`, `DeploymentStatusWorker`, `EnvironmentSynchronizationWorker`
  - Scheduler: `EPiServer.PaaS.Scheduler/` manages background job scheduling across workers.
  - Service bus messaging helpers: `EPiServer.PaaS.Infrastructure.ServiceBus.*` (Base, Sending) implement transport plumbing; contracts still live in `Messages`.
  - Shared service utilities: `EPiServer.PaaS.Services.Common/` provides hosting utilities shared across service hosts.
  - Console utilities: `EPiServer.PaaS.Console/` (admin/maintenance tooling).
- Cross‑component contracts live in `EPiServer.PaaS.Messages/` (message/event DTOs) and shared config in `Infrastructure.Configuration`.
- Tests: MSpec based. Naming: `*.Specs` (unit/spec style) and `*.Integration.Specs` (integration). Keep new tests consistent.
  - UI / end‑to‑end tests: `EPiServer.PaaS.Portal.Tests.UI` & `EPiServer.PaaS.Portal.QATests.UI/` cover browser-level scenarios.
    - Test infrastructure: `Portal.Tests.UI.Models/` (page object models), `Portal.Tests.UI.Infrastructure/` (test harness utilities)
    - Keep infra models segregated from business logic.

## Build & Test Workflows
- Build using `dotnet build` (SDK version 8.0.400 specified in `PaaS/global.json`).
- Run tests using `dotnet test` or helper scripts.
- Helper scripts (see `PaaS/buildscripts/`):
  - **Testing:**
    - `RunUnitTests.ps1` - Executes all `*.Specs` unit test projects
    - `RunIntegrationTests.ps1` - Runs `*.Integration.Specs` projects (requires external services)
    - `RunUITests.ps1` - Browser-based UI automation tests
    - `RunLocalUITestContainer.ps1` - Hosts portal locally (https://localhost:44348/) for UI test development
  - **Build & Quality:**
    - `Build.ps1` - Aggregate build + SonarQube analysis (inspect `sonarQubeExclusions` before moving UI assets)
  - **Release Management:**
    - `RunPaasVersionBump.ps1` - Automated version increment in `version.props` + git tag
    - `CreateReleaseNotes.ps1` - Generates release notes from commits/PRs
    - `PublishReleaseNotes.ps1` - Publishes release notes to distribution channels
  - **Deployment:**
    - `DeployCloudService.ps1`, `DeployPackages.ps1`, `Swap.ps1` - Azure deployment automation
    - See also: `PaaS/buildscripts/docker/` and `PaaS/buildscripts/Aspire/` for containerization

## Conventions & Patterns
- Target frameworks: Libraries use `netstandard2.0`; tests target `net8.0` (see `Application.Specs.csproj`). Don't upgrade selectively—coordinate across solution.
- Provider SDK isolation: Azure/sdk packages only in `Infrastructure.*` projects (example: `Infrastructure.AzureManagement` heavy Azure.* refs). Keep application/core layers free of direct cloud SDK dependencies.
- Specs: Use Machine.Specifications + FakeItEasy + Should helpers. Organize by behavior context; mimic existing `*.Specs` structure. Avoid xUnit/NUnit unless explicitly requested.
 - Embedded resources (email templates, json/plan mapping definitions, policy json, HTML fragments) appear in multiple projects (`Application.csproj`, `ProvisioningWorker.Base.csproj`, some test infra). When adding resources:
   - Add explicit `<EmbeddedResource Include=...>` (or `<EmbeddedResource Remove=...>`) entries
   - Only set `CopyToOutputDirectory` when runtime file path access is required (otherwise load via assembly stream)
   - Follow existing naming patterns (e.g. `dm-*.json` for deployment model variants)
- ReSharper settings: Root `PaaS.sln.DotSettings` + per `*.Specs` copy (sync via `Utilties/CopySpecsDotSettingsToSpecProjects.ps1`). Update root then propagate.
- Exclusions for static analysis (Sonar): See `Build.ps1` `sonarQubeExclusions`. Respect these paths when reorganizing assets (keep generated/vendor UI assets excluded).
- Messaging / DTO boundaries: Add cross-component contracts to `Messages` project; don't reference infrastructure packages from contracts.
 - Worker pattern: Shared orchestration/templates in `.Base` project; thin host under `Services.<Worker>` referencing ServiceDefaults via Aspire.
 - Portal frontend build: Reuse `gulpfile.js` / `webpack.config.js`; avoid adding parallel bundler stacks.
 - Versioning: Use `RunPaasVersionBump.ps1` instead of manual edits to `version.props`.

## When Adding Code
- New infrastructure integration? Create under `EPiServer.PaaS.Infrastructure.<Provider>` mirroring existing projects; expose provider-neutral interfaces in `Infrastructure.Common` if shared.
- New domain/application behavior? Prefer placing orchestration in `Application` and pure domain types in `Core`.
- New spec: Place in appropriate `*.Specs` project; if it touches external services, consider an `.Integration.Specs` project variant.
- Version bump with functional changes impacting deployments: run version bump script instead of manual edit.
 - New worker? Factor reusable orchestration into a `.Base` project if multiple host variants are expected; otherwise implement directly in `Services.<Name>Worker` with minimal `Program.cs`.
 - Data shape change (Mongo/persistence): implement migration logic under `Migrations` and cover with specs (`Migrations.Specs`).

## AI Response Guidance
- Always cite concrete file paths (e.g., `PaaS/buildscripts/Build.ps1`) for build/test answers.
- Prefer existing script usage over inventing new CLI steps.
- Before suggesting dependency upgrades, note central versioning and cross-project impact.
- For Azure resource operations, point to `Infrastructure.AzureManagement` abstractions; don't inject raw SDK calls into higher layers.
- Keep changes minimal and aligned with netstandard2.0 compatibility unless coordinated migration.
- Reference Aspire projects (`EPiserver.PaaS.Aspire.*`) when explaining hosting defaults / instrumentation.
- For UI automation, cite the correct UI test project (`EPiServer.PaaS.Portal.Tests.UI` or `Portal.QATests.UI`) rather than generic guidance.

## Common Scenarios & Examples

### Scenario: Adding a new Azure service integration
**Steps:**
1. Create new project: `EPiServer.PaaS.Infrastructure.<ServiceName>/` (netstandard2.0)
2. Add corresponding test project: `EPiServer.PaaS.Infrastructure.<ServiceName>.Specs/` (net8.0 + MSpec)
3. If integration tests needed: `EPiServer.PaaS.Infrastructure.<ServiceName>.Integration.Specs/`
4. Add Azure SDK packages ONLY to Infrastructure project (not Application/Core)
5. Create abstraction interfaces in `Infrastructure.Common` if shared across providers
6. Reference from `Application` layer via interface, never concrete Azure types
7. Write specs following existing MSpec patterns in similar Infrastructure projects

**Example file locations:**
- Implementation: `PaaS/EPiServer.PaaS.Infrastructure.AzureManagement/AzureResourceManager.cs`
- Specs: `PaaS/EPiServer.PaaS.Infrastructure.AzureManagement.Specs/AzureResourceManagerSpecs.cs`

### Scenario: Adding a new background worker
**Steps:**
1. Create `.Base` project if worker has reusable orchestration logic:
   - `EPiServer.PaaS.<WorkerName>Worker.Base/` (netstandard2.0)
   - Include embedded resources (JSON templates, email HTML, etc.)
2. Create service host:
   - `EPiServer.PaaS.Services.<WorkerName>Worker/` (net8.0)
   - Reference: `.Base` project + `Aspire.ServiceDefaults` + `Services.Common`
   - Minimal `Program.cs` with `AddServiceDefaults()` call
3. Add message contracts to `EPiServer.PaaS.Messages/`
4. Add specs: `EPiServer.PaaS.<WorkerName>Worker.Specs/`
5. Update solution file to include in appropriate solution folders

**Example existing workers:**
- `PaaS/EPiServer.PaaS.ProvisioningWorker.Base/` (orchestration + templates)
- `PaaS/EPiServer.PaaS.Services.ProvisioningWorker/Program.cs` (thin host)

### Scenario: Modifying database schema
**Steps:**
1. Implement migration in `EPiServer.PaaS.Migrations/`
2. Add migration spec in `EPiServer.PaaS.Migrations.Specs/`
3. Update repository/data access in `EPiServer.PaaS.DataAccess/`
4. Run migration via `PaaS/Database/RunDatabaseMigrations.ps1` (see README.md)
5. Consider backward compatibility for zero-downtime deployments

**Related projects:**
- Schema migrations: `PaaS/EPiServer.PaaS.Migrations/`
- Test harness: `PaaS/EPiServer.PaaS.Database.Integration.Base/`

### Scenario: Updating frontend UI
**Steps:**
1. Modify React/JS in `EPiServer.PaaS.Portal/ClientResources/`
2. Update LESS styles in `ClientResources/css/*.less`
3. Build frontend assets: `gulp` (runs clean, less, webpack via `gulpfile.js`)
4. Test locally: Run `RunLocalUITestContainer.ps1` → browse to https://localhost:44348/
5. Add/update UI tests in `Portal.Tests.UI/` using page object models from `Portal.Tests.UI.Models/`
6. Verify: `RunUITests.ps1`

**Build chain:**
- Entry: `PaaS/EPiServer.PaaS.Portal/gulpfile.js`
- Webpack config: `PaaS/EPiServer.PaaS.Portal/webpack.config.js`
- Output: `dist/` and `ClientResources/css/`

### Scenario: Bumping version for release
**Steps:**
1. NEVER manually edit `PaaS/version.props`
2. Run: `PaaS/buildscripts/RunPaasVersionBump.ps1` (increments + tags)
3. Generate notes: `CreateReleaseNotes.ps1`
4. Publish: `PublishReleaseNotes.ps1`
5. Commit + push tags

**Version location:** `PaaS/version.props` (auto-updated by script)

### Scenario: Searching for where functionality lives
**Common patterns:**
- Azure resource provisioning → `Infrastructure.AzureManagement` + `ProvisioningWorker.Base`
- Email sending → `Application/Common/EmailAssets/` (templates) + `Infrastructure.SendGrid` or `Infrastructure.Mail` (delivery)
- Hostname/DNS logic → `Application/Hostnames/` + `Infrastructure.CloudFlareManagement` + `Infrastructure.DnsLookup`
- Plan definitions → `Application/Plans/plans.json` (embedded resource)
- Service bus messages → `Messages/` (contracts) + `Infrastructure.ServiceBus.Sending` (publisher)
- Monitoring/health → `Aspire.ServiceDefaults` (OpenTelemetry) + `Infrastructure.Datadog`

Questions / unclear areas? Provide best guess + flag for human confirmation when wiki-only knowledge would be required.
