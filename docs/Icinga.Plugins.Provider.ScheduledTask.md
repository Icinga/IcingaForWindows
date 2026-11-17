# Icinga.Plugins.Provider.ScheduledTask

*Auto-generated from `src/Plugins/Provider/ScheduledTask/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Private helpers

- [Get-IcingaScheduledTask](#get-icingascheduledtask)

---

### Get-IcingaScheduledTask

*Private function*

**Synopsis:** Collect Windows scheduled tasks and their runtime metadata

#### Description

Get-IcingaScheduledTask is the data source for Invoke-IcingaCheckScheduledTask.
It queries all scheduled tasks via Get-ScheduledTask, filters them by TaskPath,
ExcludeTaskPath, TaskName and ExcludeTaskName (wildcards supported), and enriches
each matching task with runtime information from Get-ScheduledTaskInfo (last run
time, next run time, last task result and number of missed runs).

Run timestamps are returned both as formatted invariant strings
('yyyy/MM/dd HH:mm:ss', or '' when never run / not scheduled) and as offsets in
seconds relative to the current time (LastRunOffset counts up from the last run,
NextRunOffset counts down to the next scheduled run, 0 when unset). Tasks are
grouped by TaskPath and sorted by TaskName.

#### Parameters

**`$TaskName`**

| Name     | Type         | Description                                                  | Default |
|----------|--------------|--------------------------------------------------------------|---------|
| TaskName | System.Array | Only collect tasks matching these names (wildcards allowed). | @()     |

**`$ExcludeTaskName`**

| Name            | Type         | Description                                          | Default |
|-----------------|--------------|------------------------------------------------------|---------|
| ExcludeTaskName | System.Array | Skip tasks matching these names (wildcards allowed). | @()     |

**`$TaskPath`**

| Name     | Type         | Description                                                  | Default |
|----------|--------------|--------------------------------------------------------------|---------|
| TaskPath | System.Array | Only collect tasks matching these paths (wildcards allowed). | @()     |

**`$ExcludeTaskPath`**

| Name            | Type         | Description                                          | Default |
|-----------------|--------------|------------------------------------------------------|---------|
| ExcludeTaskPath | System.Array | Skip tasks matching these paths (wildcards allowed). | @()     |

#### Outputs

System.Collections.Hashtable -- Hashtable with keys Tasks (hashtable keyed by
TaskPath containing arrays of task hashtables) and TaskNames (array of known task
names after path and exclude filtering), or an IcingaError when querying failed.

#### Examples

```powershell
PS> Get-IcingaScheduledTask -TaskPath '\Icinga\*'

Returns all scheduled tasks under the \Icinga\ task path hierarchy.
```

#### Notes

Windows-only. Relies on Get-ScheduledTask and Get-ScheduledTaskInfo from the
ScheduledTasks module.

*Source: [src/Plugins/Provider/ScheduledTask/Private/Get-IcingaScheduledTask.ps1](../src/Plugins/Provider/ScheduledTask/Private/Get-IcingaScheduledTask.ps1)*

