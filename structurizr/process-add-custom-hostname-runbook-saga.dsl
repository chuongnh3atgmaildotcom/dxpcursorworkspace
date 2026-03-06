// Process: Add custom hostname — runbook saga (9 components)
// Operation: Add custom hostname (Portal) triggers provisioning; provisioning may start a runbook (e.g. Set-CloudflareBaseline); runbook execution is orchestrated by the saga.
// See: process-add-custom-hostname-runbook-saga.md for per-step actors, triggers, actions, causality, artifacts, modes, boundaries.
//
// Saga entity (configuration/policy + state): RunbookCommand message types, RunbookJob entity, timeout/lock policy.
// Implementation: Producer (RunbookManager + runbook classes), Message transport (Service Bus), Consumer host (Environment Synchronization Worker).

dynamic paas * {
    title "Add custom hostname — runbook saga"
    description "Process that uses the nine saga components: (1) Saga handler HandleRunbookSaga, (2) Messages RunbookCommand.cs, (3) Saga state RunbookJob, (4) Saga state persistence RunbookJobRepository → MongoDB runbookjobs, (5) Message transport Azure Service Bus, (6) Producer RunbookManager + runbook (e.g. SetCloudflareBaselineRunbook), (7) Distributed lock DistributedLockManager → MongoDB distributedlocks, (8) External system AzureAutomationManager → Azure Automation, (9) Consumer host Environment Synchronization Worker. Completion/error: IRunbookEventHandler via Notify on Finished/Failed."

    1: ops -> portal "Add/complete custom hostname (UI)"
    2: portal -> message_bus "Send CompleteCustomHostName (deploymentId, projectProvisioningId, ...)"
    3: provisioning_worker -> message_bus "Consume CompleteCustomHostName"
    4: provisioning_worker -> runbook_manager "StartNewJob (e.g. SetCloudflareBaselineRunbookParameters); RunbookManager.Run"
    5: runbook_manager -> mongodb.saga_store "Create RunbookJob; persist (IRunbookJobRepository)"
    6: runbook_manager -> message_bus "Send RunbookJobStart (RunbookName, Parameters, JobRecordId, ...)"
    7: message_bus -> env_sync_worker "Deliver RunbookJobStart"
    8: env_sync_worker -> saga_handler "Dispatch HandleMessage(RunbookJobStart)"
    9: saga_handler -> mongodb.lock_store "TryLock(ResourceLockName) when required"
    10: saga_handler -> mongodb.saga_store "Get RunbookJob; Save JobId, AccountName, Worker, Status"
    11: saga_handler -> azure_automation.automation_account "StartJobAsync(RunbookName, parameters, account, worker)"
    12: saga_handler -> message_bus "Send RunbookJobWaiting (JobId, JobRecordId, ...)"
    13: message_bus -> env_sync_worker "Deliver RunbookJobWaiting"
    14: saga_handler -> mongodb.saga_store "Update status"
    15: saga_handler -> azure_automation.automation_account "GetJobAsync; GetJobStreamLogAsync (poll)"
    16: saga_handler -> message_bus "Send RunbookJobInProgress (defer loop) or RunbookJobFinished / RunbookJobFailed"
    17: saga_handler -> mongodb.lock_store "Remove(ResourceLockName) on Finished/Failed"
    18: saga_handler -> message_bus "Notify(RunbookJobFinished/Failed) → IRunbookEventHandler"
    autolayout lr
}
