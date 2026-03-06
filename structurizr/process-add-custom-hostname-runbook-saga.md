<style>
  table { 
    display: block;
    width: 100%; 
    overflow-x: auto; 
  }
</style>
# Process: Add custom hostname — runbook saga

This process describes the **add custom hostname** operation and how it uses the **nine saga components**. The runbook saga orchestrates execution of a runbook (e.g. **Set-CloudflareBaseline**) in Azure Automation; the add-custom-hostname flow can trigger provisioning that starts such a runbook.

## Saga entity vs implementation

- **Saga entity (configuration/policy + state):** Message contracts (`RunbookCommand.cs`), `RunbookJob` entity, timeout and lock policy.
- **Implementation:** Producer (RunbookManager + runbook classes), message transport (Azure Service Bus), consumer host (Environment Synchronization Worker).

## Nine components mapped to the process


| #   | Component              | Description                                     | *.cs / driver                                                                            |
| --- | ---------------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------------- |
| 1   | Saga handler           | Single class handling all runbook message types | `HandleRunbookSaga.cs`                                                                   |
| 2   | Messages               | Saga commands/events                            | `RunbookCommand.cs` (RunbookJobStart, Waiting, InProgress, Finished, Failed, …)          |
| 3   | Saga state (entity)    | Per-job state                                   | `RunbookJob.cs` (Core/Models)                                                            |
| 4   | Saga state persistence | Load/save saga state                            | `IRunbookJobRepository` / `RunbookJobRepository.cs` → **MongoDB** `runbookjobs`          |
| 5   | Message transport      | Carry commands/events                           | **Azure Service Bus** (`IBus` / `IAspireBus`)                                            |
| 6   | Producer               | Create job, send RunbookJobStart                | `RunbookManager.cs` + runbook (e.g. `SetCloudflareBaselineRunbook.cs`)                   |
| 7   | Distributed lock       | Optional single-runbook concurrency             | `IDistributedLockManager` / `DistributedLockManager.cs` → **MongoDB** `distributedlocks` |
| 8   | External system        | Execute runbook                                 | `IAzureAutomationManager` / `AzureAutomationManager.cs` → **Azure Automation**           |
| 9   | Consumer host          | Process that runs the saga handler              | Environment Synchronization Worker (`WorkerRole.cs` → `WorkerServiceBase`)               |


Completion/error: `IRunbookEventHandler` / `DeploymentRunbookHandler`; `_bus.Notify(RunbookJobFinished | RunbookJobFailed)`.

---

## Per-step process descriptor

For each step, the table below captures: **actors**, **triggers**, **actions**, **causality**, **artifacts**, **modes** (active / passive), **boundaries** (repo or system).


| Step | Actors                               | Triggers                                                      | Actions                                                                                       | Causality                                                                                                  | Artifacts                                                                   | Modes                                 | Boundaries                                            |
| ---- | ------------------------------------ | ------------------------------------------------------------- | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------- | ----------------------------------------------------- |
| 1    | Operator                             | Manual: add/complete custom hostname in UI                    | Use Portal hostname flow                                                                      | Next: Portal sends message                                                                                 | Hostname, deploymentId, projectId                                           | Active                                | PaaS Portal (PaaS repo)                               |
| 2    | PaaS Portal                          | User action (step 1)                                          | Send **CompleteCustomHostName** to bus                                                        | Next: Provisioning Worker consumes                                                                         | CompleteCustomHostName (DeploymentId, ProjectProvisioningId, …)             | Active                                | PaaS → Service Bus                                    |
| 3    | Provisioning Worker                  | **CompleteCustomHostName** message                            | Handle message; may run provisioning (e.g. ProjectZoneBaseline) that starts a runbook         | Next: Call RunbookManager (runbook.StartNewJob)                                                            | Message payload                                                             | Passive (consume) then active         | PaaS repo (Services.ProvisioningWorker)               |
| 4    | Provisioning Worker → RunbookManager | Provisioning logic (e.g. ProvisionProjectZoneBaselineHandler) | **RunbookManager.Run**: build RunbookJobStart; create RunbookJob record; send RunbookJobStart | Next: Persist state (5), send message (6)                                                                  | SetCloudflareBaselineRunbookParameters, RunbookName, Parameters, TimeOut, … | Active                                | PaaS repo (Infrastructure.Runbooks)                   |
| 5    | RunbookManager                       | Run(IRunbookJob)                                              | **IRunbookJobRepository.Create**: insert RunbookJob into MongoDB `runbookjobs`                | Next: Send RunbookJobStart (6)                                                                             | RunbookJob (Id, RunbookName, Parameters, TimeOut, TimeOutInQueue)           | Active                                | PaaS → MongoDB                                        |
| 6    | RunbookManager                       | After Create                                                  | **IBus.Send(RunbookJobStart)** (or IAspireBus)                                                | Next: Message Bus delivers to consumer (7)                                                                 | RunbookJobStart (JobRecordId, RunbookName, Parameters, ResourceLockName, …) | Active                                | PaaS → Azure Service Bus                              |
| 7    | Message Bus                          | RunbookJobStart enqueued                                      | Deliver message to Environment Synchronization Worker                                         | Next: Worker dispatches to saga handler (8)                                                                | RunbookJobStart                                                             | Passive (transport)                   | Azure Service Bus                                     |
| 8    | Environment Synchronization Worker   | RunbookJobStart received                                      | **HandleRunbookSaga.HandleMessage(RunbookJobStart)** invoked                                  | Next: Lock (9), load/save state (10), call Azure (11)                                                      | RunbookJobStart                                                             | Passive then active                   | PaaS repo (Services.EnvironmentSynchronizationWorker) |
| 9    | HandleRunbookSaga                    | Before starting job (when ResourceLockName set)               | **IDistributedLockManager.TryLock**; if failed, defer message                                 | Next: If lock acquired (or not required), load job record (10)                                             | ResourceLockName, JobRecordId                                               | Active                                | PaaS → MongoDB `distributedlocks`                     |
| 10   | HandleRunbookSaga                    | After lock (or skip)                                          | **IRunbookJobRepository.Get(JobRecordId)**; set AccountName, Worker; **Save**                 | Next: Start job in Azure Automation (11)                                                                   | RunbookJob (JobId, AccountName, Worker, Parameters)                         | Active                                | PaaS → MongoDB `runbookjobs`                          |
| 11   | HandleRunbookSaga                    | After state updated                                           | **IAzureAutomationManager.StartJobAsync**(RunbookName, parameters, account, worker)           | Next: Send RunbookJobWaiting (12)                                                                          | RunbookName, parameters, account, worker                                    | Active                                | PaaS → Azure Automation API                           |
| 12   | HandleRunbookSaga                    | After StartJobAsync returns JobId                             | **IBus.Send(RunbookJobWaiting)**                                                              | Next: Consumer receives Waiting (13), then InProgress loop                                                 | RunbookJobWaiting (JobId, JobRecordId, JobInProgressPollingInterval)        | Active                                | PaaS → Azure Service Bus                              |
| 13   | Message Bus                          | RunbookJobWaiting enqueued                                    | Deliver to Environment Synchronization Worker                                                 | Next: Saga handler HandleMessage(RunbookJobWaiting) (14–16)                                                | RunbookJobWaiting                                                           | Passive                               | Azure Service Bus                                     |
| 14   | HandleRunbookSaga                    | RunbookJobWaiting received                                    | Update **RunbookJob** status in MongoDB                                                       | Next: Poll Azure (15), then send InProgress or Finished/Failed (16)                                        | RunbookJob (Status)                                                         | Active                                | PaaS → MongoDB `runbookjobs`                          |
| 15   | HandleRunbookSaga                    | InProgress polling loop                                       | **GetJobAsync**, **GetJobStreamLogAsync**; update RunbookJob (status, streams)                | Next: If finished → RunbookJobFinished; if failed → RunbookJobFailed; else defer RunbookJobInProgress (16) | JobId, AccountName; OutputStream, ErrorStream, WarningStream                | Active                                | PaaS → Azure Automation API                           |
| 16   | HandleRunbookSaga                    | Job finished or failed (or defer)                             | **IBus.Send(RunbookJobInProgress)** (defer) or **Send(RunbookJobFinished                      | RunbookJobFailed)**                                                                                        | Next: If Finished/Failed, release lock (17), notify (18)                    | RunbookJobFinished / RunbookJobFailed | Active                                                |
| 17   | HandleRunbookSaga                    | On RunbookJobFinished or RunbookJobFailed                     | **IDistributedLockManager.Remove**(ResourceLockName, JobRecordId)                             | Next: Notify subscribers (18)                                                                              | ResourceLockName, JobRecordId                                               | Active                                | PaaS → MongoDB `distributedlocks`                     |
| 18   | HandleRunbookSaga                    | After lock removed                                            | **IBus.Notify(RunbookJobFinished                                                              | RunbookJobFailed)** → **IRunbookEventHandler** / DeploymentRunbookHandler                                  | Saga step complete; UI/workers react (e.g. update deployment status)        | RunbookJobFinished / RunbookJobFailed | Active                                                |


---

## Boundaries (repos / systems)

- **PaaS repo:** Portal, Provisioning Worker, RunbookManager, Environment Synchronization Worker, HandleRunbookSaga, RunbookJobRepository, DistributedLockManager, AzureAutomationManager.
- **Azure Service Bus:** Message transport (RunbookJobStart, RunbookJobWaiting, RunbookJobInProgress, RunbookJobFinished, RunbookJobFailed).
- **MongoDB:** Saga state (`runbookjobs`), distributed locks (`distributedlocks`).
- **Azure Automation:** Runbook execution (e.g. **Set-EPiCloudflareBaseline.ps1** in dxc-deployment-automation).

