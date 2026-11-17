<#
.SYNOPSIS
Declare the default set of performance counters shipped with the module

.DESCRIPTION
`Register-IcingaDefaultPerformanceCounter` declares a small, broadly-available set of
performance counters (processor, memory and physical disk) by calling
`New-IcingaPerformanceCounter`. It serves as the reference example of how a component
declares the counters it needs and gives the startup discovery step and the warm-up path a
concrete set to work with. Additional components declare their own counters the same way.

.OUTPUTS
None -- Registers the default counter paths in the global store.

.EXAMPLE
PS> Register-IcingaDefaultPerformanceCounter

.NOTES
The literal counter list here is what the discovery step reads from the compiled kernel. The
set is intentionally minimal and generic; it is an example, not a fixed contract.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Register-IcingaDefaultPerformanceCounter()
{
    New-IcingaPerformanceCounter -Counter @(
        '\Processor(_Total)\% Processor Time',
        '\Memory\Available Bytes',
        '\PhysicalDisk(*)\Disk Reads/sec',
        '\PhysicalDisk(*)\Disk Writes/sec'
    );
}
