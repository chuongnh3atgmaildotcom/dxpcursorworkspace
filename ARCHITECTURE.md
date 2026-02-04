# DXC Deployment Automation – Multi-repo Architecture

This workspace is primarily focused on **DXC (Digital Experience Cloud) deployment automation**. This document describes the C4 architecture model and job/API flows across repos.

---

## C4 Architecture Maps

### Level 1: System Context Diagram

Shows the DXC deployment system and its external users and systems.

```mermaid
C4Context
    title System Context - DXC Deployment Automation

    Person(ops, "DevOps / Operator", "Initiates deployments, manages DXC environments")
    Person(dev, "Developer", "Uses EpiCloud PowerShell for deployments")

    System(dxc, "DXC Deployment System", "Orchestrates Optimizely DXC deployments on Azure")

    System_Ext(azure, "Azure", "Web Apps, SQL, Storage, Automation Accounts")
    System_Ext(cms, "CMS App", "Optimizely CMS content application")
    System_Ext(commerce, "Commerce App", "Optimizely Commerce application")

    Rel(ops, dxc, "Manages deployments via")
    Rel(dev, dxc, "Deploys via EpiCloud API")
    Rel(dxc, azure, "Provisions and deploys to")
    Rel(dxc, cms, "Deploys code/config to")
    Rel(dxc, commerce, "Deploys code/config to")
```

---

### Level 2: Container Diagram

Shows the main containers (repos/apps) within the DXC deployment system.

```mermaid
C4Container
    title Container Diagram - DXC Deployment Automation

    Person(ops, "DevOps / Operator")
    Person(dev, "Developer")

    System_Boundary(dxc_system, "DXC Deployment System") {
        Container(paas_portal, "PaaS Portal", "ASP.NET", "Web UI for deployment management")
        Container(paas_api, "PaaS API", "REST/ASP.NET", "Deployment API, receives Start/Complete/Reset")
        Container(paas_worker, "PaaS Worker", "Background Service", "Handles messages, starts runbook jobs")
        Container(msg_bus, "Message Bus", "Azure Service Bus", "StartEnvironmentSynchronization, etc.")
        Container(runbooks, "Runbooks", "PowerShell / Azure Automation", "Start-EPiDeployment, Copy-Database, etc.")
    }

    System_Ext(epicloud, "EpiCloud", "PowerShell module calling PaaS API")
    System_Ext(azure_auto, "Azure Automation", "Runs runbooks on Hybrid Worker")

    Rel(ops, paas_portal, "Uses")
    Rel(dev, epicloud, "Uses")
    Rel(epicloud, paas_api, "Calls deployment API")
    Rel(paas_portal, paas_api, "Calls")
    Rel(paas_api, msg_bus, "Sends StartEnvironmentSynchronization")
    Rel(paas_worker, msg_bus, "Consumes messages")
    Rel(paas_worker, azure_auto, "Starts runbook job")
    Rel(azure_auto, runbooks, "Executes")
    Rel(runbooks, azure_auto, "Uses Azure APIs")
```

---

## C4 Dynamic Sequence Diagrams

These diagrams show how elements collaborate at runtime for specific flows. Interactions are numbered in order.

### Flow 1: Start Deployment (Portal → Worker → Runbook)

```mermaid
C4Dynamic
    title Start Deployment - Portal to Runbook

    Person(ops, "Operator")
    Container(portal, "PaaS Portal", "ASP.NET")
    Container(api, "PaaS API", "REST")
    ContainerQueue(msg_bus, "Message Bus", "Service Bus")
    Container(worker, "PaaS Worker", "Background")
    Container(runbook, "Start-EPiDeployment", "PowerShell")
    System_Ext(azure, "Azure APIs")

    RelIndex(1, ops, portal, "Clicks Start Deployment")
    RelIndex(2, portal, api, "POST deployment request")
    RelIndex(3, api, msg_bus, "Send StartEnvironmentSynchronization")
    RelIndex(4, worker, msg_bus, "Consume message")
    RelIndex(5, worker, runbook, "Start runbook job (SourceWebApp, IncludeCode, ...)")
    RelIndex(6, runbook, azure, "Copy blobs, swap slots, etc.")
```

---

### Flow 2: Start Deployment (EpiCloud → PaaS API)

```mermaid
C4Dynamic
    title Start Deployment - EpiCloud to PaaS

    Person(dev, "Developer")
    Container(epicloud, "EpiCloud", "PowerShell")
    Container(paas_api, "PaaS API", "REST")
    ContainerQueue(msg_bus, "Message Bus", "Service Bus")
    Container(worker, "PaaS Worker", "Background")
    Container(runbook, "Start-EPiDeployment", "PowerShell")

    RelIndex(1, dev, epicloud, "Start-EpiDeployment -TargetEnvironment Production")
    RelIndex(2, epicloud, paas_api, "POST /deployments with ClientKey, ProjectId, DeploymentPackage")
    RelIndex(3, paas_api, msg_bus, "Create EnvironmentSynchronization, send StartEnvironmentSynchronization")
    RelIndex(4, worker, msg_bus, "Handle message")
    RelIndex(5, worker, runbook, "Invoke runbook with params")
```

---

### Flow 3: Complete Deployment & Poll Status

```mermaid
C4Dynamic
    title Complete Deployment & Poll Status

    Person(dev, "Developer")
    Container(epicloud, "EpiCloud", "PowerShell")
    Container(paas_api, "PaaS API", "REST")
    Container(worker, "PaaS Worker", "Background")
    Container(complete_runbook, "Complete-EPiDeployment", "PowerShell")
    Container(get_runbook, "Get-JobOutput", "PowerShell")

    RelIndex(1, dev, epicloud, "Complete-EpiDeployment -DeploymentId xyz")
    RelIndex(2, epicloud, paas_api, "POST complete deployment")
    RelIndex(3, paas_api, worker, "Send finalize/complete message")
    RelIndex(4, worker, complete_runbook, "Run Complete-EPiDeployment runbook")
    RelIndex(5, epicloud, paas_api, "GET deployment status (polling)")
    RelIndex(6, epicloud, paas_api, "Get runbook job output via Get-JobOutput")
```

---

## Alternative: Mermaid Sequence Diagrams

If C4Dynamic render incorrectly, use these standard sequence diagrams for the same flows.

### Sequence: Start Deployment (Portal)

```mermaid
sequenceDiagram
    participant Ops as DevOps Operator
    participant Portal as PaaS Portal
    participant API as PaaS API
    participant Bus as Message Bus
    participant Worker as PaaS Worker
    participant Runbook as Start-EPiDeployment
    participant Azure as Azure APIs

    Ops->>Portal: Click Start Deployment
    Portal->>API: POST deployment request
    API->>Bus: Send StartEnvironmentSynchronization
    Worker->>Bus: Consume message
    Worker->>Runbook: Start runbook (SourceWebApp, IncludeCode, ...)
    Runbook->>Azure: Copy blobs, swap slots
```

### Sequence: EpiCloud Start Deployment

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant EpiCloud as EpiCloud PowerShell
    participant API as PaaS API
    participant Bus as Message Bus
    participant Worker as PaaS Worker
    participant Runbook as Start-EPiDeployment

    Dev->>EpiCloud: Start-EpiDeployment -TargetEnvironment Production
    EpiCloud->>API: POST /deployments (ClientKey, ProjectId, DeploymentPackage)
    API->>Bus: StartEnvironmentSynchronization
    Worker->>Bus: Handle message
    Worker->>Runbook: Invoke runbook with params
```

### Sequence: Complete Deployment

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant EpiCloud as EpiCloud
    participant API as PaaS API
    participant Worker as PaaS Worker
    participant Runbook as Complete-EPiDeployment

    Dev->>EpiCloud: Complete-EpiDeployment -DeploymentId xyz
    EpiCloud->>API: POST complete deployment
    API->>Worker: Finalize message
    Worker->>Runbook: Run Complete-EPiDeployment
    loop Poll until done
        EpiCloud->>API: GET deployment status
    end
```

---

## Repos in this Workspace

| Repo | Role |
|------|------|
| **PaaS** | Portal, API, workers; orchestration and deployment lifecycle |
| **cms** | CMS application / content |
| **commerce** | Commerce application |
| **content-cloudplatform** | Content cloud platform / headless |
| **dxc-deployment-automation** | Runbooks, automation, Azure Automation / deployment scripts |
| **EpiCloud** | PowerShell module for Epi Cloud API (e.g. Start-EpiDeployment, Connect-EpiCloud) |

---

## Job / API Call Chain

### Start Deployment (source → target)

1. **Entry point**: PaaS Portal UI, PaaS API, or EpiCloud PowerShell (`Start-EpiDeployment`)
2. **PaaS** Portal or API receives request → `SynchronizationService` creates `EnvironmentSynchronization`, sends `StartEnvironmentSynchronization` message.
3. **PaaS** Environment sync worker handles message → starts runbook job, invokes **dxc-deployment-automation** runbook (e.g. `Start-EPiDeployment`) with params (SourceWebApp, IncludeCode, resource groups, etc.).
4. **dxc-deployment-automation** runbooks execute in Azure Automation (or Hybrid Worker), call Azure/APIs as needed.
5. **EpiCloud** PowerShell module can be used externally to call PaaS deployment API (e.g. `Start-EpiDeployment`, `Complete-EpiDeployment`).

### Other flows

- **Complete deployment**: `Complete-EpiDeployment` → PaaS API → worker → `Complete-EPiDeployment` runbook
- **Reset deployment**: `Reset-EpiDeployment` → PaaS API
- **Database export**: `Start-EpiDatabaseExport`, `Get-EpiDatabaseExport` → PaaS API

---

## Key Contracts (Messages, APIs, Runbooks)

| From | To | Contract (name / route / runbook) |
|------|----|-----------------------------------|
| PaaS (Portal/API) | PaaS (Worker) | `StartEnvironmentSynchronization` |
| PaaS (Worker) | dxc-deployment-automation | Runbook `Start-EPiDeployment`, params e.g. SourceWebApp, IncludeCode |
| PaaS (Worker) | dxc-deployment-automation | Runbook `Complete-EPiDeployment` |
| External / EpiCloud | PaaS | Deployment API (start, complete, reset, get status) |

---

## Where to Look for Flow Logic

- **PaaS**: `EPiServer.PaaS.Application` (use cases, services), `EPiServer.PaaS.*.Base` (message handlers, sagas), `EPiServer.PaaS.Messages` (commands/events).
- **dxc-deployment-automation**: `ScriptRunbooks/`, runbook names match what PaaS sends. See `AGENTS.md` and `ScriptRunbooks/AGENTS.md`.
- **EpiCloud**: `source/Public/*.ps1` (e.g. `Start-EpiDeployment.ps1`), calls to PaaS API.

---

*Update this file when you add new flows or change how repos interact.*
