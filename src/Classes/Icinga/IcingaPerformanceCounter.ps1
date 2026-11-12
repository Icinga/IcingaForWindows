<#
.SYNOPSIS
Live wrapper around a single Windows performance counter handle

.DESCRIPTION
IcingaPerformanceCounterEntry owns exactly one `System.Diagnostics.PerformanceCounter`
handle for a fully-qualified counter path (category, optional instance, counter). It
implements the prime-then-read pattern required for accurate rate counters: `Prime`
takes the first (throwaway) sample, and `Read` takes the second sample and returns the
uniform value hashtable. The class never throws on counter errors -- failures are
surfaced through the `error` key of the returned hashtable -- and disposes its handle
through `Dispose`.

The handle is created and read on a single thread only (the performance-counter
daemon, or a transient one-shot resolver). The class holds no global state and is
therefore safe to construct in any runspace, mirroring the IcingaUnit class.

.OUTPUTS
IcingaPerformanceCounterEntry -- A single initialized counter wrapper.

.EXAMPLE
PS> [IcingaPerformanceCounterEntry]::new('\Processor(_Total)\% Processor Time', 'Processor', '_Total', '% Processor Time')

.NOTES
`System.Diagnostics.PerformanceCounter` is IDisposable; the handle is created on the
`Handle` field and released in `Dispose`. Never share a single instance across threads.
#>
class IcingaPerformanceCounterEntry
{
    [string]$FullName                              = '';
    [string]$Category                              = '';
    [string]$Instance                              = '';
    [string]$Counter                               = '';
    [System.Diagnostics.PerformanceCounter]$Handle = $null;
    [bool]$Primed                                  = $false;
    [string]$LastError                             = '';

    <#
    .SYNOPSIS
    Create a counter entry for a fully-qualified counter path

    .DESCRIPTION
    Stores the parsed components of a counter path. The underlying handle is created
    lazily on the first `Prime` call, not in the constructor.

    .PARAMETER FullName
| Name     | Type          | Description                                       | Default |
|----------|---------------|---------------------------------------------------|---------|
| FullName | System.String | The complete counter path, e.g. '\Cat(Inst)\Ctr'. |         |

    .PARAMETER Category
| Name     | Type          | Description                       | Default |
|----------|---------------|-----------------------------------|---------|
| Category | System.String | The performance counter category. |         |

    .PARAMETER Instance
| Name     | Type          | Description                                      | Default |
|----------|---------------|--------------------------------------------------|---------|
| Instance | System.String | The instance name, or empty for single-instance. |         |

    .PARAMETER Counter
| Name    | Type          | Description               | Default |
|---------|---------------|---------------------------|---------|
| Counter | System.String | The counter name to read. |         |

    .OUTPUTS
    IcingaPerformanceCounterEntry -- The configured, not-yet-primed entry.

    .EXAMPLE
    PS> [IcingaPerformanceCounterEntry]::new('\Memory\Available Bytes', 'Memory', '', 'Available Bytes')
    #>
    IcingaPerformanceCounterEntry([string]$FullName, [string]$Category, [string]$Instance, [string]$Counter)
    {
        $this.FullName = $FullName;
        $this.Category = $Category;
        $this.Instance = $Instance;
        $this.Counter  = $Counter;
    }

    <#
    .SYNOPSIS
    Create the handle and take the first (priming) sample

    .DESCRIPTION
    Instantiates the `System.Diagnostics.PerformanceCounter` handle on first use and
    calls `NextValue`/`NextSample` once to prime rate counters. The first sample of a
    rate counter is meaningless, so callers must wait a short interval before calling
    `Read`. Priming errors are swallowed and surface later through `Read`.

    .OUTPUTS
    None -- Populates the `Handle` field and sets `Primed`.

    .EXAMPLE
    PS> $entry.Prime()

    .NOTES
    Callers are expected to batch a single shared sleep after priming many entries,
    rather than sleeping per entry.
    #>
    [void] Prime()
    {
        try {
            if ($null -eq $this.Handle) {
                $this.Handle              = [System.Diagnostics.PerformanceCounter]::new();
                $this.Handle.CategoryName = $this.Category;
                $this.Handle.CounterName  = $this.Counter;

                if (-not [string]::IsNullOrEmpty($this.Instance)) {
                    $this.Handle.InstanceName = $this.Instance;
                }
            }

            $this.Handle.NextValue()  | Out-Null;
            $this.Handle.NextSample() | Out-Null;
            $this.LastError = '';
        } catch {
            # A priming failure is reported on the next Read call through the error key.
            $this.LastError = $_.Exception.Message;
            $Error.Clear();
        }

        $this.Primed = $true;
    }

    <#
    .SYNOPSIS
    Read the current counter value as the uniform result hashtable

    .DESCRIPTION
    Takes the second sample of the counter and returns a hashtable with the fixed keys
    `value`, `sample`, `help`, `type` and `error`. `value` is rounded to six decimals.
    The method never throws -- any exception is captured into the `error` key while the
    remaining keys keep their defaults.

    .OUTPUTS
    System.Collections.Hashtable -- Keys value, sample, help, type, error.

    .EXAMPLE
    PS> $result = $entry.Read()
    #>
    [hashtable] Read()
    {
        [hashtable]$Result = @{
            'value'  = [decimal]0;
            'sample' = $null;
            'help'   = $null;
            'type'   = $null;
            'error'  = $null;
        };

        if ($null -eq $this.Handle) {
            if ([string]::IsNullOrEmpty($this.LastError)) {
                $Result['error'] = 'Counter not initialized';
            } else {
                $Result['error'] = $this.LastError;
            }

            return $Result;
        }

        try {
            $CounterValue = $this.Handle.NextValue();
            if ($null -eq $CounterValue) {
                $CounterValue = 0;
            }

            $Result['value']  = [math]::Round([decimal]$CounterValue, 6);
            $Result['sample'] = $this.Handle.NextSample();
            $Result['help']   = $this.Handle.CounterHelp;
            $Result['type']   = [string]$this.Handle.CounterType;
        } catch {
            $Result['error'] = $_.Exception.Message;
        }

        return $Result;
    }

    <#
    .SYNOPSIS
    Release the underlying performance counter handle

    .DESCRIPTION
    Disposes the `System.Diagnostics.PerformanceCounter` handle and clears the field so
    the entry can be safely discarded. Safe to call multiple times.

    .OUTPUTS
    None -- Releases the native handle.

    .EXAMPLE
    PS> $entry.Dispose()
    #>
    [void] Dispose()
    {
        if ($null -ne $this.Handle) {
            $this.Handle.Dispose();
            $this.Handle = $null;
        }
    }
}

<#
.SYNOPSIS
Snapshot reader for every instance and counter of one performance counter category

.DESCRIPTION
IcingaPerformanceCounterCategory reads a whole category with one `ReadCategory` call
and keeps the previous and the current snapshot. A value is calculated from both
snapshots exactly like `PerformanceCounter.NextValue` calculates it from its last two
samples, so rate counters such as '% Processor Time' need no handle per instance.

Wildcard counter paths ('\Process(*)\% Processor Time') are read through this class.
Every `NextValue` of a single handle reads the complete category data from the system,
so one handle per instance costs one category read per instance and refresh. For a
category with hundreds of instances (Process) that took seconds per refresh, while one
`ReadCategory` returns all instances and counters in a few milliseconds.

Instances are matched between the two snapshots by name. In categories with an
'ID Process' counter (Process, Thread) an instance whose process id changed between
the snapshots is treated as new, because Windows renumbers 'name#n' instances when a
process with the same name exits; its rate counters then read 0 until the next
snapshot.

.OUTPUTS
IcingaPerformanceCounterCategory -- The snapshot reader of one category.

.EXAMPLE
PS> $Snapshot = [IcingaPerformanceCounterCategory]::new('Process')
PS> $Snapshot.Prime(); Start-Sleep -Milliseconds 250; $Snapshot.Refresh()
PS> $Snapshot.Read('svchost', '% Processor Time')

.NOTES
Holds no native counter handles. The counter help texts are read once through
`GetCounters` and those handles are disposed right away. Like the counter entries an
instance is used on one thread only.
#>
class IcingaPerformanceCounterCategory
{
    [string]$Category                                              = '';
    [System.Diagnostics.PerformanceCounterCategory]$Reader         = $null;
    [System.Diagnostics.InstanceDataCollectionCollection]$Previous = $null;
    [System.Diagnostics.InstanceDataCollectionCollection]$Current  = $null;
    [datetime]$ReadTime                                            = [datetime]::MinValue;
    [hashtable]$Help                                               = $null;
    [string]$LastError                                             = '';

    <#
    .SYNOPSIS
    Create a snapshot reader for a category

    .DESCRIPTION
    Stores the category name. The category is read for the first time by `Prime`.

    .PARAMETER Category
| Name     | Type          | Description                       | Default |
|----------|---------------|-----------------------------------|---------|
| Category | System.String | The performance counter category. |         |

    .OUTPUTS
    IcingaPerformanceCounterCategory -- The not yet primed reader.

    .EXAMPLE
    PS> [IcingaPerformanceCounterCategory]::new('Processor Information')
    #>
    IcingaPerformanceCounterCategory([string]$Category)
    {
        $this.Category = $Category;
    }

    <#
    .SYNOPSIS
    Take the first snapshot of the category

    .DESCRIPTION
    Reads the category once. Rate counters need a second snapshot before they return a
    meaningful value, so callers wait a short interval and call `Refresh`. A category
    that cannot be read is remembered in `LastError` instead of throwing.

    .OUTPUTS
    None -- Populates the current snapshot.

    .EXAMPLE
    PS> $Snapshot.Prime()
    #>
    [void] Prime()
    {
        try {
            $this.Reader    = [System.Diagnostics.PerformanceCounterCategory]::new($this.Category);
            $this.Current   = $this.Reader.ReadCategory();
            $this.ReadTime  = [datetime]::UtcNow;
            $this.LastError = '';
        } catch {
            $this.LastError = $_.Exception.Message;
            $Error.Clear();
        }
    }

    <#
    .SYNOPSIS
    Take a new snapshot and keep the current one as the previous snapshot

    .DESCRIPTION
    Values are calculated over the interval between the two snapshots. A failed read
    keeps both snapshots and stores the reason in `LastError`.

    .OUTPUTS
    None -- Advances the snapshots.

    .EXAMPLE
    PS> $Snapshot.Refresh()
    #>
    [void] Refresh()
    {
        if ($null -eq $this.Reader -or $null -eq $this.Current) {
            $this.Prime();
            return;
        }

        try {
            $Snapshot       = $this.Reader.ReadCategory();
            $this.Previous  = $this.Current;
            $this.Current   = $Snapshot;
            $this.ReadTime  = [datetime]::UtcNow;
            $this.LastError = '';
        } catch {
            $this.LastError = $_.Exception.Message;
            $Error.Clear();
        }
    }

    <#
    .SYNOPSIS
    Return the age of the current snapshot in milliseconds

    .DESCRIPTION
    Returns the milliseconds since the last successful read, or the largest double when
    the category was never read.

    .OUTPUTS
    System.Double -- Age of the current snapshot.

    .EXAMPLE
    PS> $Snapshot.AgeMilliseconds()
    #>
    [double] AgeMilliseconds()
    {
        if ($null -eq $this.Current) {
            return [double]::MaxValue;
        }

        return ([datetime]::UtcNow - $this.ReadTime).TotalMilliseconds;
    }

    <#
    .SYNOPSIS
    Return the instance names of the current snapshot

    .DESCRIPTION
    Returns every instance name with its original casing. The pseudo instance that
    .NET reports for single-instance categories is left out, so a single-instance
    category returns no instances, like `GetInstanceNames`.

    .OUTPUTS
    System.String[] -- The instance names of the current snapshot.

    .EXAMPLE
    PS> $Snapshot.GetInstanceNames()
    #>
    [string[]] GetInstanceNames()
    {
        $Names = [System.Collections.Generic.List[string]]::new();

        if ($null -eq $this.Current) {
            return $Names.ToArray();
        }

        foreach ($Collection in $this.Current.Values) {
            foreach ($Data in $Collection.Values) {
                if ($Data.InstanceName -ne 'systemdiagnosticsperfcounterlibsingleinstance') {
                    $Names.Add($Data.InstanceName);
                }
            }

            # Every counter of a snapshot holds the same instances.
            break;
        }

        return $Names.ToArray();
    }

    <#
    .SYNOPSIS
    Read one counter of one instance as the uniform result hashtable

    .DESCRIPTION
    Calculates the value from the previous and the current snapshot and returns a
    hashtable with the keys `value`, `sample`, `help`, `type` and `error`, the same
    shape as IcingaPerformanceCounterEntry.Read. Without a usable previous sample the
    value is calculated from the current sample alone. The method never throws.

    .PARAMETER Instance
| Name     | Type          | Description           | Default |
|----------|---------------|-----------------------|---------|
| Instance | System.String | The instance to read. |         |

    .PARAMETER Counter
| Name    | Type          | Description          | Default |
|---------|---------------|----------------------|---------|
| Counter | System.String | The counter to read. |         |

    .OUTPUTS
    System.Collections.Hashtable -- Keys value, sample, help, type, error.

    .EXAMPLE
    PS> $Snapshot.Read('_Total', '% Processor Time')
    #>
    [hashtable] Read([string]$Instance, [string]$Counter)
    {
        [hashtable]$Result = @{
            'value'  = [decimal]0;
            'sample' = $null;
            'help'   = $null;
            'type'   = $null;
            'error'  = $null;
        };

        if ($null -eq $this.Current) {
            if ([string]::IsNullOrEmpty($this.LastError)) {
                $Result['error'] = 'Counter not initialized';
            } else {
                $Result['error'] = $this.LastError;
            }

            return $Result;
        }

        $Collection = $this.Current[$Counter];

        if ($null -eq $Collection) {
            $Result['error'] = [string]::Format('The counter "{0}" does not exist in the category "{1}"', $Counter, $this.Category);
            return $Result;
        }

        $Data = $Collection[$Instance];

        if ($null -eq $Data) {
            $Result['error'] = [string]::Format('The instance "{0}" does not exist in the category "{1}"', $Instance, $this.Category);
            return $Result;
        }

        try {
            $Sample        = $Data.Sample;
            $PreviousData  = $this.FindPrevious($Instance, $Counter);
            [double]$Value = 0;

            if ($null -eq $PreviousData) {
                $Value = [System.Diagnostics.CounterSample]::Calculate($Sample);
            } else {
                $Value = [System.Diagnostics.CounterSample]::Calculate($PreviousData.Sample, $Sample);
            }

            $Result['value']  = [math]::Round([decimal]$Value, 6);
            $Result['sample'] = $Sample;
            $Result['help']   = $this.GetHelp($Counter, $Instance);
            $Result['type']   = [string]$Sample.CounterType;
        } catch {
            $Result['error'] = $_.Exception.Message;
        }

        return $Result;
    }

    <#
    .SYNOPSIS
    Find the previous instance data of a counter that belongs to the same instance

    .DESCRIPTION
    Returns the instance data of the previous snapshot, or $null when there is no
    previous snapshot, the instance is new, or (in categories with an 'ID Process'
    counter) the name now belongs to a different process.

    .PARAMETER Instance
| Name     | Type          | Description        | Default |
|----------|---------------|--------------------|---------|
| Instance | System.String | The instance name. |         |

    .PARAMETER Counter
| Name    | Type          | Description       | Default |
|---------|---------------|-------------------|---------|
| Counter | System.String | The counter name. |         |

    .OUTPUTS
    System.Diagnostics.InstanceData -- The previous data, or $null.

    .EXAMPLE
    PS> $Snapshot.FindPrevious('svchost#3', '% Processor Time')
    #>
    hidden [System.Diagnostics.InstanceData] FindPrevious([string]$Instance, [string]$Counter)
    {
        if ($null -eq $this.Previous) {
            return $null;
        }

        $Collection = $this.Previous[$Counter];

        if ($null -eq $Collection) {
            return $null;
        }

        $Data = $Collection[$Instance];

        if ($null -eq $Data) {
            return $null;
        }

        $PreviousIds = $this.Previous['ID Process'];
        $CurrentIds  = $this.Current['ID Process'];

        if ($null -ne $PreviousIds -and $null -ne $CurrentIds) {
            $PreviousId = $PreviousIds[$Instance];
            $CurrentId  = $CurrentIds[$Instance];

            if ($null -eq $PreviousId -or $null -eq $CurrentId -or $PreviousId.RawValue -ne $CurrentId.RawValue) {
                return $null;
            }
        }

        return $Data;
    }

    <#
    .SYNOPSIS
    Return the help text of a counter

    .DESCRIPTION
    Reads the help texts of all counters of the category once, through the handles
    returned by `GetCounters` for the given instance, and disposes those handles right
    away. Later calls answer from the cached texts.

    .PARAMETER Counter
| Name    | Type          | Description       | Default |
|---------|---------------|-------------------|---------|
| Counter | System.String | The counter name. |         |

    .PARAMETER Instance
| Name     | Type          | Description                                 | Default |
|----------|---------------|---------------------------------------------|---------|
| Instance | System.String | An existing instance used to list counters. |         |

    .OUTPUTS
    System.String -- The help text, or $null when it cannot be read.

    .EXAMPLE
    PS> $Snapshot.GetHelp('% Processor Time', '_Total')
    #>
    hidden [string] GetHelp([string]$Counter, [string]$Instance)
    {
        if ($null -eq $this.Help) {
            $this.Help = @{ };

            try {
                foreach ($Handle in $this.Reader.GetCounters($Instance)) {
                    $this.Help[$Handle.CounterName] = $Handle.CounterHelp;
                    $Handle.Dispose();
                }
            } catch {
                # Help texts are informational only; the value stays valid without them.
                $Error.Clear();
            }
        }

        return $this.Help[$Counter];
    }
}

<#
.SYNOPSIS
Central, thread-confined registry and reader for Windows performance counters

.DESCRIPTION
IcingaPerformanceCounter is the manager that owns every live counter handle for the
module. Concrete counter paths get one handle each; wildcard instance paths are read
through one IcingaPerformanceCounterCategory snapshot per category, because a handle
reads the whole category on every sample and large categories (Process) would cost one
category read per instance. New counters and categories are primed with a single
shared warm-up sleep, values are returned in the uniform result shape, rate counters
are kept warm, and transient instances (a removable disk appearing or disappearing)
are picked up by the category snapshots.

The manager is created and used exclusively on the performance-counter daemon thread,
so its internal `ConcurrentDictionary` is never mutated concurrently. Callers on other
threads never touch the manager directly -- they exchange requests and responses through
the thread-safe queues in the global runtime store. The self-contained one-shot
`ResolveOnce` supports command-line usage where no daemon is running.

.OUTPUTS
IcingaPerformanceCounter -- The counter manager instance.

.EXAMPLE
PS> $manager = [IcingaPerformanceCounter]::new()
PS> $manager.Resolve(@('\Processor(_Total)\% Processor Time'))

.NOTES
Every handle is created, sampled and disposed on one thread. All class methods are
self-contained and perform no logging or global-state access so they remain safe under
the module's runspace model.
#>
class IcingaPerformanceCounter
{
    [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$Counters   = $null;
    [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$Categories = $null;
    [int]$WarmupMilliseconds                                                        = 250;

    <#
    .SYNOPSIS
    Create an empty counter manager

    .DESCRIPTION
    Initializes the thread-safe registries for counter handles and category snapshots.
    Nothing is read until `Warmup`, `Resolve` or `Reconcile` is called.

    .OUTPUTS
    IcingaPerformanceCounter -- An empty manager.

    .EXAMPLE
    PS> [IcingaPerformanceCounter]::new()
    #>
    IcingaPerformanceCounter()
    {
        $this.Counters   = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new();
        $this.Categories = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new();
    }

    <#
    .SYNOPSIS
    Parse a counter path into its category, instance and counter components

    .DESCRIPTION
    Splits a fully-qualified counter path of the form '\Category\Counter',
    '\Category(Instance)\Counter' or '\\<LocalHost>\Category\Counter' into its parts.
    Local machine prefixes ('\\.\', '\\localhost\', '\\127.0.0.1\', '\\::1\' and
    '\\<MachineName>\') are accepted and stripped automatically; remote host prefixes
    are rejected. Returns a hashtable with `Category`, `Instance`, `Counter` and a
    `Valid` flag. Invalid input yields `Valid = $false` instead of throwing.

    .PARAMETER Path
| Name | Type          | Description                       | Default |
|------|---------------|-----------------------------------|---------|
| Path | System.String | The counter path string to parse. |         |

    .OUTPUTS
    System.Collections.Hashtable -- Keys Category, Instance, Counter, Valid.

    .EXAMPLE
    PS> [IcingaPerformanceCounter]::ParsePath('\PhysicalDisk(0 C:)\Disk Reads/sec')
    #>
    static [hashtable] ParsePath([string]$Path)
    {
        [hashtable]$Result = @{
            'Category' = '';
            'Instance' = '';
            'Counter'  = '';
            'Valid'    = $false;
        };

        if ([string]::IsNullOrEmpty($Path)) {
            return $Result;
        }

        if ($Path.StartsWith('\\')) {
            [int]$NextSlash = $Path.IndexOf('\', 2);

            if ($NextSlash -le 2) {
                return $Result;
            }

            [string]$Machine = $Path.Substring(2, $NextSlash - 2);

            if ($Machine -ne '.' -and -not $Machine.Equals('localhost', [System.StringComparison]::OrdinalIgnoreCase) -and $Machine -ne '127.0.0.1' -and $Machine -ne '::1' -and -not $Machine.Equals([System.Environment]::MachineName, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $Result;
            }

            $Path = $Path.Substring($NextSlash);
        }

        [string[]]$Parts = $Path.Split('\');

        # A valid path starts with a backslash, so the first split element is empty and
        # there are three elements: '', category(+instance), counter.
        if ($Parts.Count -ne 3 -or -not [string]::IsNullOrEmpty($Parts[0])) {
            return $Result;
        }

        [string]$CategoryPart = $Parts[1];
        $Result['Counter']    = $Parts[2];

        if ($CategoryPart.Contains('(') -or $CategoryPart.Contains(')')) {
            [int]$Open  = $CategoryPart.IndexOf('(');
            [int]$Close = $CategoryPart.LastIndexOf(')');

            if ($Open -gt 0 -and $Close -gt $Open -and $Close -eq ($CategoryPart.Length - 1)) {
                $Result['Category'] = $CategoryPart.Substring(0, $Open);
                $Result['Instance'] = $CategoryPart.Substring($Open + 1, $Close - $Open - 1);
            } else {
                return $Result;
            }
        } else {
            $Result['Category'] = $CategoryPart;
        }

        if (-not [string]::IsNullOrEmpty($Result['Category']) -and -not [string]::IsNullOrEmpty($Result['Counter'])) {
            $Result['Valid'] = $true;
        }

        return $Result;
    }

    <#
    .SYNOPSIS
    Normalize a counter path by stripping any local machine prefix

    .DESCRIPTION
    Parses the given counter path and returns its canonical machine-less form
    ('\Category\Counter' or '\Category(Instance)\Counter'). Invalid paths are returned
    unchanged.

    .PARAMETER Path
| Name | Type          | Description                           | Default |
|------|---------------|---------------------------------------|---------|
| Path | System.String | The counter path string to normalize. |         |

    .OUTPUTS
    System.String -- The canonical counter path without a machine prefix.

    .EXAMPLE
    PS> [IcingaPerformanceCounter]::NormalizePath('\\.\Memory\Available Bytes')
    #>
    static [string] NormalizePath([string]$Path)
    {
        $CounterType = 'IcingaPerformanceCounter' -as [type];
        $Parsed      = $CounterType::ParsePath($Path);

        if (-not $Parsed.Valid) {
            return $Path;
        }

        if ([string]::IsNullOrEmpty($Parsed.Instance)) {
            return ('\{0}\{1}' -f $Parsed.Category, $Parsed.Counter);
        }

        return ('\{0}({1})\{2}' -f $Parsed.Category, $Parsed.Instance, $Parsed.Counter);
    }

    <#
    .SYNOPSIS
    Check whether a performance counter category exists on the local system

    .DESCRIPTION
    Accepts either a plain category name ('Processor') or a full counter path
    ('\Processor(*)\% Processor Time' or '\\.\Processor(_Total)\% Processor Time') and
    returns $true when the category exists and is accessible on this system, or $false
    otherwise. Never throws.

    .PARAMETER Category
| Name     | Type          | Description                                 | Default |
|----------|---------------|---------------------------------------------|---------|
| Category | System.String | The category name or counter path to check. |         |

    .OUTPUTS
    System.Boolean -- $true when the category exists on the system; $false otherwise.

    .EXAMPLE
    PS> [IcingaPerformanceCounter]::CategoryExists('Processor')
    #>
    static [bool] CategoryExists([string]$Category)
    {
        if ([string]::IsNullOrWhiteSpace($Category)) {
            return $false;
        }

        [string]$TargetCategory = $Category.Trim();

        if ($TargetCategory.StartsWith('\')) {
            $CounterType = 'IcingaPerformanceCounter' -as [type];
            $Parsed      = $CounterType::ParsePath($TargetCategory);

            if ($Parsed.Valid) {
                $TargetCategory = $Parsed.Category;
            } else {
                return $false;
            }
        }

        if ([string]::IsNullOrWhiteSpace($TargetCategory)) {
            return $false;
        }

        try {
            $CategoryObject = [System.Diagnostics.PerformanceCounterCategory]::new($TargetCategory);

            if ($null -eq $CategoryObject -or $null -eq $CategoryObject.CategoryType) {
                return $false;
            }

            return $true;
        } catch {
            $Error.Clear();
            return $false;
        }
    }

    <#
    .SYNOPSIS
    Return the last error recorded for a category snapshot

    .DESCRIPTION
    Returns the `LastError` string of a registered category snapshot when priming or
    refreshing that category failed (for example when the category does not exist or
    access is denied), or an empty string when the category snapshot is healthy.

    .PARAMETER Category
| Name     | Type          | Description                       | Default |
|----------|---------------|-----------------------------------|---------|
| Category | System.String | The performance counter category. |         |

    .OUTPUTS
    System.String -- The last error message for the category, or an empty string.

    .EXAMPLE
    PS> $manager.GetCategoryError('Processor')
    #>
    [string] GetCategoryError([string]$Category)
    {
        if ([string]::IsNullOrWhiteSpace($Category)) {
            return 'Category name is empty';
        }

        if ($this.Categories.ContainsKey($Category)) {
            $Snapshot = $this.Categories[$Category];

            if ($null -ne $Snapshot -and -not [string]::IsNullOrEmpty($Snapshot.LastError)) {
                return $Snapshot.LastError;
            }
        }

        return '';
    }

    <#
    .SYNOPSIS
    Expand a counter path into the concrete per-instance paths that exist right now

    .DESCRIPTION
    For a wildcard path (instance '*') this queries the live instance names of the
    category and returns one full path per instance. For a concrete or single-instance
    path it returns the path unchanged. Categories that cannot be read yield an empty
    array rather than throwing.

    .PARAMETER Path
| Name | Type          | Description                           | Default |
|------|---------------|---------------------------------------|---------|
| Path | System.String | The (possibly wildcard) counter path. |         |

    .OUTPUTS
    System.String[] -- The concrete counter paths currently present.

    .EXAMPLE
    PS> $manager.ExpandPath('\PhysicalDisk(*)\Disk Reads/sec')
    #>
    [string[]] ExpandPath([string]$Path)
    {
        $CounterType = 'IcingaPerformanceCounter' -as [type];
        $Parsed      = $CounterType::ParsePath($Path);

        if (-not $Parsed.Valid) {
            return @();
        }

        if ($Parsed.Instance -ne '*') {
            return @($Path);
        }

        [string[]]$Expanded = @();

        try {
            $CategoryObject = [System.Diagnostics.PerformanceCounterCategory]::new($Parsed.Category);
            foreach ($InstanceName in $CategoryObject.GetInstanceNames()) {
                $Expanded += ('\{0}({1})\{2}' -f $Parsed.Category, $InstanceName, $Parsed.Counter);
            }
        } catch {
            # The category is not available on this system; report no live instances.
            $Expanded = @();
        }

        return $Expanded;
    }

    <#
    .SYNOPSIS
    Build a counter entry for a concrete counter path

    .DESCRIPTION
    Parses the path and constructs an IcingaPerformanceCounterEntry. Returns `$null` for
    invalid paths so the caller can skip them.

    .PARAMETER Path
| Name | Type          | Description                | Default |
|------|---------------|----------------------------|---------|
| Path | System.String | The concrete counter path. |         |

    .OUTPUTS
    IcingaPerformanceCounterEntry -- The new entry, or $null when the path is invalid.

    .EXAMPLE
    PS> $manager.CreateEntry('\Memory\Available Bytes')
    #>
    [object] CreateEntry([string]$Path)
    {
        $CounterType = 'IcingaPerformanceCounter' -as [type];
        $EntryType   = 'IcingaPerformanceCounterEntry' -as [type];
        $Parsed      = $CounterType::ParsePath($Path);

        if (-not $Parsed.Valid) {
            return $null;
        }

        [string]$Normalized = $CounterType::NormalizePath($Path);

        return $EntryType::new($Normalized, $Parsed.Category, $Parsed.Instance, $Parsed.Counter);
    }

    <#
    .SYNOPSIS
    Ensure the given counter paths are initialized and primed

    .DESCRIPTION
    Creates and primes a handle for every new concrete path and a category snapshot for
    every new category of a wildcard path, then performs a single shared warm-up sleep
    if anything was primed. Known counters and categories are left untouched, so
    repeated calls are cheap.

    .PARAMETER Paths
| Name  | Type            | Description                           | Default |
|-------|-----------------|---------------------------------------|---------|
| Paths | System.String[] | The counter paths to ensure are warm. |         |

    .OUTPUTS
    None -- Populates the internal registry.

    .EXAMPLE
    PS> $manager.Warmup(@('\Processor(_Total)\% Processor Time'))

    .NOTES
    The single shared sleep is the reason a batch of counters costs one warm-up interval
    instead of one interval per counter.
    #>
    [void] Warmup([string[]]$Paths)
    {
        [bool]$PrimedAny = $false;
        $CounterType     = 'IcingaPerformanceCounter' -as [type];

        foreach ($Path in $Paths) {
            $Parsed = $CounterType::ParsePath($Path);

            if (-not $Parsed.Valid) {
                continue;
            }

            if ($Parsed.Instance -eq '*') {
                if ($this.AddCategory($Parsed.Category)) {
                    $PrimedAny = $true;
                }

                continue;
            }

            [string]$Normalized = $CounterType::NormalizePath($Path);

            if (-not $this.Counters.ContainsKey($Normalized)) {
                $Entry = $this.CreateEntry($Normalized);

                if ($null -ne $Entry -and $this.Counters.TryAdd($Normalized, $Entry)) {
                    $Entry.Prime();
                    $PrimedAny = $true;
                }
            }
        }

        if ($PrimedAny) {
            Start-Sleep -Milliseconds $this.WarmupMilliseconds;
        }
    }

    <#
    .SYNOPSIS
    Create and prime the snapshot of a category if it does not exist yet

    .DESCRIPTION
    Adds a category snapshot to the registry and takes its first read. Returns $true
    when a new snapshot was primed, so the caller knows a warm-up sleep is needed.

    .PARAMETER Category
| Name     | Type          | Description                       | Default |
|----------|---------------|-----------------------------------|---------|
| Category | System.String | The performance counter category. |         |

    .OUTPUTS
    System.Boolean -- $true when a new snapshot was created and primed.

    .EXAMPLE
    PS> $manager.AddCategory('Process')
    #>
    [bool] AddCategory([string]$Category)
    {
        if ($this.Categories.ContainsKey($Category)) {
            return $false;
        }

        $CategoryType = 'IcingaPerformanceCounterCategory' -as [type];
        $Snapshot     = $CategoryType::new($Category);

        if (-not $this.Categories.TryAdd($Category, $Snapshot)) {
            return $false;
        }

        $Snapshot.Prime();

        return $true;
    }

    <#
    .SYNOPSIS
    Read a single concrete counter path from the registry

    .DESCRIPTION
    Returns the uniform result hashtable for a concrete counter path. If the path is not
    present in the registry, a result with a populated `error` key is returned.

    .PARAMETER Path
| Name | Type          | Description                | Default |
|------|---------------|----------------------------|---------|
| Path | System.String | The concrete counter path. |         |

    .OUTPUTS
    System.Collections.Hashtable -- Keys value, sample, help, type, error.

    .EXAMPLE
    PS> $manager.ReadPath('\Memory\Available Bytes')
    #>
    [hashtable] ReadPath([string]$Path)
    {
        $CounterType        = 'IcingaPerformanceCounter' -as [type];
        [string]$Normalized = $CounterType::NormalizePath($Path);

        if ($this.Counters.ContainsKey($Normalized)) {
            $Entry = $this.Counters[$Normalized];

            if ($null -ne $Entry) {
                return $Entry.Read();
            }
        }

        return @{
            'value'  = [decimal]0;
            'sample' = $null;
            'help'   = $null;
            'type'   = $null;
            'error'  = 'Counter not initialized';
        };
    }

    <#
    .SYNOPSIS
    Warm up and read a set of counter paths into the uniform result structure

    .DESCRIPTION
    Ensures every requested counter is warm, then reads it. A concrete path maps to its
    flat five-key hashtable; a wildcard path maps to a nested hashtable keyed by each
    instance path of the category snapshot. The outer hashtable is keyed by the
    originally requested path so callers can correlate requests and responses.

    A category snapshot that is at least `WarmupMilliseconds` old is refreshed before it
    is read, once per request. Values are therefore always calculated over at least that
    interval; the daemon additionally refreshes every snapshot on each `Sample`.

    .PARAMETER Paths
| Name  | Type            | Description                | Default |
|-------|-----------------|----------------------------|---------|
| Paths | System.String[] | The counter paths to read. |         |

    .OUTPUTS
    System.Collections.Hashtable -- Keyed by requested path; flat or nested per path.

    .EXAMPLE
    PS> $manager.Resolve(@('\PhysicalDisk(*)\Disk Reads/sec'))
    #>
    [hashtable] Resolve([string[]]$Paths)
    {
        $this.Warmup($Paths);

        [hashtable]$Result    = @{ };
        [hashtable]$ReadCache = @{ };
        $CounterType          = 'IcingaPerformanceCounter' -as [type];

        foreach ($Path in $Paths) {
            $Parsed = $CounterType::ParsePath($Path);

            if ($Parsed.Valid -and $Parsed.Instance -eq '*') {
                [hashtable]$Group = @{ };
                $Snapshot         = $null;

                if ($this.Categories.ContainsKey($Parsed.Category)) {
                    $Snapshot = $this.Categories[$Parsed.Category];
                }

                if ($null -ne $Snapshot) {
                    if ($Snapshot.AgeMilliseconds() -ge $this.WarmupMilliseconds) {
                        $Snapshot.Refresh();
                    }

                    foreach ($InstanceName in $Snapshot.GetInstanceNames()) {
                        $Expanded = ('\{0}({1})\{2}' -f $Parsed.Category, $InstanceName, $Parsed.Counter);

                        if (-not $ReadCache.ContainsKey($Expanded)) {
                            $ReadCache[$Expanded] = $Snapshot.Read($InstanceName, $Parsed.Counter);
                        }

                        $Group[$Expanded] = $ReadCache[$Expanded];
                    }
                }

                $Result[$Path] = $Group;
            } else {
                [string]$Normalized = $CounterType::NormalizePath($Path);

                if (-not $ReadCache.ContainsKey($Normalized)) {
                    $ReadCache[$Normalized] = $this.ReadPath($Normalized);
                }

                $Result[$Path] = $ReadCache[$Normalized];
            }
        }

        return $Result;
    }

    <#
    .SYNOPSIS
    Take a fresh sample of every registered counter to keep rate values current

    .DESCRIPTION
    Calls `NextValue` on each live handle and refreshes every category snapshot, so the
    next read computes an accurate rate over the refresh interval. Sampling errors are
    ignored -- dead instances are removed separately by `Reconcile`, and a category
    snapshot keeps its last read when a refresh fails.

    .OUTPUTS
    None -- Advances the internal sample of every counter.

    .EXAMPLE
    PS> $manager.Sample()
    #>
    [void] Sample()
    {
        foreach ($Key in @($this.Counters.Keys)) {
            $Entry = $this.Counters[$Key];

            if ($null -ne $Entry -and $null -ne $Entry.Handle) {
                try {
                    $Entry.Handle.NextValue() | Out-Null;
                } catch {
                    # Ignore; Reconcile drops instances that no longer exist.
                    $Error.Clear();
                }
            }
        }

        foreach ($Key in @($this.Categories.Keys)) {
            $Snapshot = $this.Categories[$Key];

            if ($null -ne $Snapshot) {
                $Snapshot.Refresh();
            }
        }
    }

    <#
    .SYNOPSIS
    Synchronize the live registry with the currently registered counter paths

    .DESCRIPTION
    Adds and primes a handle for every registered concrete path and a category snapshot
    for every category of a registered wildcard path, and removes handles and snapshots
    that are no longer wanted (a counter that was evicted from the registration list).
    Instances that appear or disappear, such as a newly inserted removable disk, are
    covered by the category snapshots. New handles and snapshots share a single warm-up
    sleep.

    .PARAMETER RegisteredPaths
| Name            | Type            | Description                                 | Default |
|-----------------|-----------------|---------------------------------------------|---------|
| RegisteredPaths | System.String[] | The counter paths that should be kept warm. |         |

    .OUTPUTS
    None -- Adds and removes counter handles to match the desired set.

    .EXAMPLE
    PS> $manager.Reconcile(@('\PhysicalDisk(*)\Disk Reads/sec'))
    #>
    [void] Reconcile([string[]]$RegisteredPaths)
    {
        $Desired           = [System.Collections.Generic.HashSet[string]]::new();
        $DesiredCategories = [System.Collections.Generic.HashSet[string]]::new();
        $CounterType       = 'IcingaPerformanceCounter' -as [type];

        foreach ($Path in $RegisteredPaths) {
            $Parsed = $CounterType::ParsePath($Path);

            if (-not $Parsed.Valid) {
                continue;
            }

            if ($Parsed.Instance -eq '*') {
                [void]$DesiredCategories.Add($Parsed.Category);
            } else {
                [void]$Desired.Add($CounterType::NormalizePath($Path));
            }
        }

        [bool]$PrimedAny = $false;

        foreach ($Category in $DesiredCategories) {
            if ($this.AddCategory($Category)) {
                $PrimedAny = $true;
            }
        }

        foreach ($Wanted in $Desired) {
            if (-not $this.Counters.ContainsKey($Wanted)) {
                $Entry = $this.CreateEntry($Wanted);

                if ($null -ne $Entry -and $this.Counters.TryAdd($Wanted, $Entry)) {
                    $Entry.Prime();
                    $PrimedAny = $true;
                }
            }
        }

        if ($PrimedAny) {
            Start-Sleep -Milliseconds $this.WarmupMilliseconds;
        }

        foreach ($Key in @($this.Counters.Keys)) {
            if (-not $Desired.Contains($Key)) {
                [object]$Stale = $null;

                if ($this.Counters.TryRemove($Key, [ref]$Stale) -and $null -ne $Stale) {
                    $Stale.Dispose();
                }
            }
        }

        foreach ($Key in @($this.Categories.Keys)) {
            if (-not $DesiredCategories.Contains($Key)) {
                [object]$StaleCategory = $null;
                $this.Categories.TryRemove($Key, [ref]$StaleCategory) | Out-Null;
            }
        }
    }

    <#
    .SYNOPSIS
    Dispose every counter handle and clear the registry

    .DESCRIPTION
    Releases all native performance counter handles held by the manager and empties the
    handle and category registries. Called on daemon shutdown and by the transient
    one-shot resolver.

    .OUTPUTS
    None -- Releases all native handles.

    .EXAMPLE
    PS> $manager.Dispose()
    #>
    [void] Dispose()
    {
        foreach ($Key in @($this.Counters.Keys)) {
            $Entry = $this.Counters[$Key];

            if ($null -ne $Entry) {
                $Entry.Dispose();
            }
        }

        $this.Counters.Clear();
        $this.Categories.Clear();
    }

    <#
    .SYNOPSIS
    Resolve counter values once without a shared registry or background daemon

    .DESCRIPTION
    Creates a throwaway manager, warms and reads the requested counters on the calling
    thread, disposes every handle, and returns the uniform result structure. This is the
    inline fallback used when no performance-counter daemon is running (for example a
    plugin invoked once from the command line). Because it is fully self-contained it
    shares no state with the daemon and is safe on any thread.

    .PARAMETER Paths
| Name  | Type            | Description                     | Default |
|-------|-----------------|---------------------------------|---------|
| Paths | System.String[] | The counter paths to read once. |         |

    .PARAMETER WarmupMilliseconds
| Name               | Type         | Description                                   | Default |
|--------------------|--------------|-----------------------------------------------|---------|
| WarmupMilliseconds | System.Int32 | Shared warm-up sleep between the two samples. | 250     |

    .OUTPUTS
    System.Collections.Hashtable -- Same shape as Resolve.

    .EXAMPLE
    PS> [IcingaPerformanceCounter]::ResolveOnce(@('\Processor(_Total)\% Processor Time'), 250)
    #>
    static [hashtable] ResolveOnce([string[]]$Paths, [int]$WarmupMilliseconds)
    {
        $CounterType                = 'IcingaPerformanceCounter' -as [type];
        $Manager                    = $CounterType::new();
        $Manager.WarmupMilliseconds = $WarmupMilliseconds;

        try {
            return $Manager.Resolve($Paths);
        } finally {
            $Manager.Dispose();
        }
    }
}
