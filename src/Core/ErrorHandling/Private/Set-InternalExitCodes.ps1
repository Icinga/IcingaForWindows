<#
.SYNOPSIS
Initialize the module's internal return code table

.DESCRIPTION
Populates `(Get-GlobalRuntimeVariable).Public.ReturnCodes` with a
centralized hashtable of semantic return-code entries used throughout
our module. Each entry contains a numeric code, a short message, a
longer description, severity and area metadata. The function is
idempotent and will return immediately if the table is already set.

.OUTPUTS
None -- Populates (Get-GlobalRuntimeVariable).Public.ReturnCodes as a side effect.

.EXAMPLE
PS> Set-InternalExitCodes

Ensures the return-code table is initialized; exits immediately if the table
is already populated.

.NOTES
Private helper used by error-handling and logging routines; safe to call
multiple times because it will not overwrite an existing table.
#>
function Set-InternalExitCodes()
{
    if ($null -ne (Get-GlobalRuntimeVariable).Public.ReturnCodes) {
        return;
    }

    (Get-GlobalRuntimeVariable).Public.ReturnCodes = @{
        'ConfigPresent' = @{
            'Code'     = 0;
            'Message'  = 'Module configuration found';
            'Severity' = 'Audit';
        };
        'ConfigMissing' = @{
            'Code'     = 0;
            'Message'  = 'Module configuration was not found';
            'Severity' = 'Info';
        };
        'EventLogAreaNotSet' = @{
            'Code'     = 10;
            'Message'  = 'The event log area was not set for this log entry';
            'Severity' = 'Warning';
            'Area'     = 'Logging'
        };
        'EventLogGenericLog' = @{
            'Code'     = 15;
            'Message'  = 'A generic event log entry was created';
            'Severity' = 'Info';
            'Area'     = 'Logging'
        };
        'AccessGranted' = @{
            'Code'     = 20;
            'Message'  = 'Access to location granted';
            'Severity' = 'Audit';
            'Area'     = 'Security'
        };
        'AccessViolation' = @{
            'Code'     = 21;
            'Message'  = 'Access violation occurred while accessing file or folder. This location is not accessible by the module';
            'Severity' = 'Error';
            'Area'     = 'Security'
        };
        # Code 22 is used during logging in Write-SecureFile.ps1 for warning inside the write loop
        # Code 23 is used during logging in Read-SecureFile.ps1 for warning inside the read loop
        'WriteFileLockException' = @{
            'Code'     = 24;
            'Message'  = 'The specified file could not be written.';
            'Severity' = 'Warning';
            'Area'     = 'Security'
        };
        'WriteFileSuccess' = @{
            'Code'     = 25;
            'Message'  = 'The specified file was written successfully.';
            'Severity' = 'Info';
            'Area'     = 'Security'
        };
        'ObjectCreationFailed' = @{
            'Code'     = 30;
            'Message'  = 'The object could not be created at desired location';
            'Severity' = 'Error';
            'Area'     = 'Security'
        };
        'ObjectCreationSucceeded' = @{
            'Code'     = 31;
            'Message'  = 'The object was created successfully at desired location';
            'Severity' = 'Audit';
            'Area'     = 'Security'
        };
        'ChildItemPathArgumentEmpty' = @{
            'Code'     = 32;
            'Message'  = 'The specified path argument for getting child items is empty';
            'Severity' = 'Error';
            'Area'     = 'Security'
        };
        'ChildItemFetchFailed' = @{
            'Code'     = 33;
            'Message'  = 'Failed to fetch child items at specified path';
            'Severity' = 'Error';
            'Area'     = 'Security'
        };
        'ChildItemFetchSucceeded' = @{
            'Code'     = 34;
            'Message'  = 'Successfully fetched child items at specified path';
            'Severity' = 'Audit';
            'Area'     = 'Security'
        };
        'RemoveItemNoPathProvided' = @{
            'Code'     = 35;
            'Message'  = 'No path was provided for removing an item';
            'Severity' = 'Error';
            'Area'     = 'Security'
        };
        'RemoveItemPathNotFound' = @{
            'Code'     = 36;
            'Message'  = 'The specified path for removing an item was not found';
            'Severity' = 'Error';
            'Area'     = 'Security'
        };
        'RemoveItemSuccess' = @{
            'Code'     = 37;
            'Message'  = 'The specified item was removed successfully';
            'Severity' = 'Audit';
            'Area'     = 'Security'
        };
        'RemoveItemFailed' = @{
            'Code'     = 38;
            'Message'  = 'Failed to remove the specified item at path';
            'Severity' = 'Error';
            'Area'     = 'Security'
        };
        'CommandNotFound' = @{
            'Code'     = 40;
            'Message'  = 'The specified command was not found on this system';
            'Severity' = 'Error';
        };
        'FileLockException' = @{
            'Code'     = 50;
            'Message'  = 'The specified file is locked by another process';
            'Severity' = 'Warning';
        };
        'ObjectReadSucceeded' = @{
            'Code'     = 51;
            'Message'  = 'The specified object was read successfully';
            'Severity' = 'Audit';
            'Area'     = 'Security'
        };
        'FileNotFound' = @{
            'Code'     = 53;
            'Message'  = 'The specified file was not found';
            'Severity' = 'Error';
        };
        'DirectoryArgumentEmpty' = @{
            'Code'     = 54;
            'Message'  = 'The specified directory argument is empty';
            'Severity' = 'Error';
        };
        'DirectoryNotFound' = @{
            'Code'     = 55;
            'Message'  = 'The specified directory was not found';
            'Severity' = 'Error';
        };
        'ServiceNotInstalled' = @{
            'Code'     = 81;
            'Message'  = 'The specified service is not installed on the system';
            'Severity' = 'Error';
        };
        'TaskSchedulerPowerShellNotFound' = @{
            'Code'     = 100;
            'Message'  = 'PowerShell Core (pwsh.exe) was not found on this system. TheTask Scheduler requires PowerShell Core to run.';
            'Severity' = 'Error';
            'Area'     = 'TaskScheduler';
        };
        'TaskSchedulerTaskNameMissing' = @{
            'Code'     = 101;
            'Message'  = 'No task name was provided for the Task Scheduler operation';
            'Severity' = 'Error';
            'Area'     = 'TaskScheduler';
        };
        'TaskSchedulerCommandStringMissing' = @{
            'Code'     = 102;
            'Message'  = 'No command string was provided for the Task Scheduler operation. Please provide a valid PowerShell command or chain to execute, e.g. "New-CertificateRotation; Restart-TCPListener".';
            'Severity' = 'Error';
            'Area'     = 'TaskScheduler';
        };
        'TaskSchedulerTimeOfDayMissing' = @{
            'Code'     = 103;
            'Message'  = 'No time of day was provided for the Task Scheduler operation. E.g. "06:00AM"';
            'Severity' = 'Error';
            'Area'     = 'TaskScheduler';
        };
        'TaskSchedulerDaysIntervalInvalid' = @{
            'Code'     = 104;
            'Message'  = 'The days interval provided for the Task Scheduler operation is invalid. It must be a positive integer greater than zero.';
            'Severity' = 'Error';
            'Area'     = 'TaskScheduler';
        };
        'TaskSchedulerTaskRegisteredSuccessfully' = @{
            'Code'     = 105;
            'Message'  = 'The Task Scheduler task was registered successfully.';
            'Severity' = 'Info';
            'Area'     = 'TaskScheduler';
        };
        'ConfigFileNotProvided' = @{
            'Code'     = 200;
            'Message'  = 'No configuration was not provided for loading';
            'Severity' = 'Error';
            'Area'     = 'Config';
        };
        'ConfigFileNotFound' = @{
            'Code'     = 201;
            'Message'  = 'The configuration file was not found for loading';
            'Severity' = 'Error';
            'Area'     = 'Config';
        };
        'ConfigFileReadFailed' = @{
            'Code'     = 202;
            'Message'  = 'Failed to read the configuration file for loading or the content is empty';
            'Severity' = 'Error';
            'Area'     = 'Config';
        };
        'ConfigFileInvalidJson' = @{
            'Code'     = 203;
            'Message'  = 'The configuration file contains invalid JSON for loading';
            'Severity' = 'Error';
            'Area'     = 'Config';
        };
        'WindowsTerminalNotInstalled' = @{
            'Code'     = 300;
            'Message'  = 'Windows Terminal is not installed on this system';
            'Severity' = 'Info';
            'Area'     = 'WindowsTerminal';
        };
        'WindowsTerminalSettingsFileNotFound' = @{
            'Code'     = 301;
            'Message'  = 'The Windows Terminal settings file was not found';
            'Severity' = 'Error';
            'Area'     = 'WindowsTerminal';
        };
        'WindowsTerminalSettingsFileReadFailed' = @{
            'Code'     = 302;
            'Message'  = 'Failed to read the Windows Terminal settings file or the content is invalid';
            'Severity' = 'Error';
            'Area'     = 'WindowsTerminal';
        };
        'WindowsTerminalProfilesAlreadyExist' = @{
            'Code'     = 303;
            'Message'  = 'The modules Windows Terminal profiles already exist';
            'Severity' = 'Info';
            'Area'     = 'WindowsTerminal';
        };
        'WindowsTerminalProfilesInstalledSuccessfully' = @{
            'Code'     = 304;
            'Message'  = 'The modules Windows Terminal profiles were installed successfully';
            'Severity' = 'Info';
            'Area'     = 'WindowsTerminal';
        };
        'ThreadCommandNotFound' = @{
            'Code'     = 832;
            'Message'  = 'Failed to start a new thread for given command, because the command was not found';
            'Severity' = 'Error';
            'Area'     = 'Threading'
        }
        'ThreadCreationFailed' = @{
            'Code'     = 833;
            'Message'  = 'A new thread could not be created for specified command';
            'Severity' = 'Error';
            'Area'     = 'Threading'
        };
        'ThreadIdEmpty' = @{
            'Code'     = 834;
            'Message'  = 'The thread could not be removed because the given thread id is empty';
            'Severity' = 'Error';
            'Area'     = 'Threading'
        };
        'ThreadNotFound' = @{
            'Code'     = 835;
            'Message'  = 'The specified thread id could not be found';
            'Severity' = 'Error';
            'Area'     = 'Threading'
        };
        'ThreadDataMissing' = @{
            'Code'     = 836;
            'Message'  = 'A new thread was tried to be created, but either the PublicSpace or ThreadId parameter was missing.';
            'Severity' = 'Error';
            'Area'     = 'Threading'
        };
        'ThreadWaitForJobMisconfiguration' = @{
            'Code'        = 837;
            'Message'     = 'The thread is marked as WaitForJobs, but you did not use "Set-ThreadProcessing" after a job was taken to update the thread state accordingly.';
            'Description' = 'Threads marked as WaitForJobs should always update their state to PROCESSING when they take a job from their queue, and back to WAITING when they are idle again. This ensures proper thread state tracking and monitoring. You have to update your code to ensure the thread state is updated accordingly after processing taking a job with "Set-ThreadProcessing" or not use the -WaitForJobs argument for this thread.';
            'Severity'    = 'Warning';
            'Area'        = 'Threading'
        };
        'UpdateTcpClientInvalid' = @{
            'Code'     = 1149;
            'Message'  = 'The TCP client provided for updating the connection is invalid.';
            'Severity' = 'Error';
            'Area'     = 'TcpStack';
        };
        'SslStreamClientInvalid' = @{
            'Code'     = 1150;
            'Message'  = 'A secure SSL stream could not be opened because the TCP client is invalid.';
            'Severity' = 'Error';
            'Area'     = 'TcpStack';
        };
        'SslStreamAlreadyOpened' = @{
            'Code'     = 1151;
            'Message'  = 'A secure SSL stream is already opened for this TCP client.';
            'Severity' = 'Warning';
            'Area'     = 'TcpStack';
        };
        'TlsCertNotFound' = @{
            'Code'     = 1152;
            'Message'  = 'The TLS/SSL certificate required for secure communication could not be found.';
            'Severity' = 'Error';
            'Area'     = 'TcpStack';
        };
        'ProtocolMissingEndpoint' = @{
            'Code'     = 1153;
            'Message'  = 'The endpoint name is missing for client to parent communication for the TCP Protocol.';
            'Severity' = 'Error';
            'Area'     = 'TcpStack';
        };
        'TlsHandshakeAsClientFailed' = @{
            'Code'        = 1154;
            'Message'     = 'The TLS handshake failed as client while trying to establish a secure connection.';
            'Description' = 'This issue commonly occurs when the certificate does not match the expected endpoint name of the target you are trying to connect to. Please verify that your endpoint name you are trying to connect to is matching the CN or SAN entries of the server certificate used by the remote node. Please also ensure that the CA certificate is trusted by your system and available.';
            'Severity'    = 'Error';
            'Area'        = 'TcpStack';
        };
        'TlsHandshakeAsServerFailed' = @{
            'Code'     = 1155;
            'Message'  = 'The TLS handshake failed as server while trying to establish a secure connection.';
            'Severity' = 'Error';
            'Area'     = 'TcpStack';
        };
        'TlsHandshakeSuccessful' = @{
            'Code'     = 1156;
            'Message'  = 'The TLS handshake was successful and a secure connection has been established.';
            'Severity' = 'Info';
            'Area'     = 'TcpStack';
        };
        'IPAddressLookupEmpty' = @{
            'Code'     = 1332;
            'Message'  = 'The given address for IP lookup is empty.';
            'Severity' = 'Error';
            'Area'     = 'TcpStack';
        };
        'IPAddressLookupFailure' = @{
            'Code'     = 1333;
            'Message'  = 'Failed to resolve IP address for hostname. No IP addresses could be found.';
            'Severity' = 'Error';
            'Area'     = 'TcpStack';
        };
        'IPAddressLookupFailedForV4AndV6' = @{
            'Code'     = 1334;
            'Message'  = 'We were able to resolve the hostname to a given address, but could not find any IPv4 or IPv6 addresses.';
            'Severity' = 'Error';
            'Area'     = 'TcpStack';
        };
        'IPAddressLookupException' = @{
            'Code'     = 1335;
            'Message'  = 'We run into an exception while trying to resolve the given hostname.';
            'Severity' = 'Error';
            'Area'     = 'TcpStack';
        };
        'ApiTcpClientNull' = @{
            'Code'     = 1500;
            'Message'  = 'The provided TCP client for the API worker queue is null';
            'Severity' = 'Warning';
            'Area'     = 'Api';
        };
        'IcingaClientConfigNotFound' = @{
            'Code'     = 2008;
            'Message'  = 'The Icinga Protocol connection configuration file was not found';
            'Severity' = 'Error';
            'Area'     = 'IcingaProtocol';
        };
        'RestApiConfigNotFound' = @{
            'Code'     = 1800;
            'Message'  = 'The REST API configuration file was not found';
            'Severity' = 'Warning';
            'Area'     = 'RestApi';
        };
        'RestApiConfigCorrupted' = @{
            'Code'     = 1801;
            'Message'  = 'The REST API configuration file is corrupted and could not be parsed';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'NoRestApiListenAddressProvided' = @{
            'Code'     = 1802;
            'Message'  = 'No REST API listen address was provided for the REST API configuration';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'NoRestApiListenPortProvided' = @{
            'Code'     = 1803;
            'Message'  = 'No REST API listen port was provided for the REST API configuration';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'InvalidRestApiWorkerCountProvided' = @{
            'Code'     = 1804;
            'Message'  = 'The provided REST API worker count is invalid. It must be between 1 and and the maximum allowed worker count';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiConfigConfigured' = @{
            'Code'     = 1805;
            'Message'  = 'REST API configuration has been successfully configured';
            'Severity' = 'Info';
            'Area'     = 'RestApi';
        };
        'RestApiConfigLoaded' = @{
            'Code'     = 1806;
            'Message'  = 'REST API configuration has been successfully loaded';
            'Severity' = 'Info';
            'Area'     = 'RestApi';
        };
        'RestApiHeaderReadTimeout' = @{
            'Code'     = 1807;
            'Message'  = 'Timeout reached while reading REST API header from stream';
            'Severity' = 'Warning';
            'Area'     = 'RestApi';
        };
        'RestApiHeaderReadError' = @{
            'Code'     = 1808;
            'Message'  = 'An error occurred while reading REST API header from stream';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiHeaderReadSuccess' = @{
            'Code'     = 1809;
            'Message'  = 'Successfully read REST API header from stream';
            'Severity' = 'Debug';
            'Area'     = 'RestApi';
        };
        'NoRestApiHeaderStringProvided' = @{
            'Code'     = 1810;
            'Message'  = 'No REST API header string was provided for parsing';
            'Severity' = 'Warning';
            'Area'     = 'RestApi';
        };
        'RestApiHeaderParseError' = @{
            'Code'     = 1811;
            'Message'  = 'An error occurred while parsing REST API header string';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'InvalidRestApiHeaderRequestLineFormat' = @{
            'Code'     = 1812;
            'Message'  = 'The REST API header request line is not in a valid format';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiHeaderParseSuccess' = @{
            'Code'     = 1813;
            'Message'  = 'Successfully parsed REST API header string';
            'Severity' = 'Debug';
            'Area'     = 'RestApi';
        };
        'NoParsedHeadersProvided' = @{
            'Code'     = 1814;
            'Message'  = 'No parsed REST API headers were provided for reading the body';
            'Severity' = 'Warning';
            'Area'     = 'RestApi';
        };
        'RestApiNoBodyToRead' = @{
            'Code'     = 1815;
            'Message'  = 'No REST API body to read as Content-Length is zero or missing';
            'Severity' = 'Debug';
            'Area'     = 'RestApi';
        };
        'RestApiBodyReadTimeout' = @{
            'Code'     = 1816;
            'Message'  = 'Timeout reached while reading REST API body from stream.';
            'Severity' = 'Warning';
            'Area'     = 'RestApi';
        };
        'RestApiBodyReadSuccess' = @{
            'Code'     = 1817;
            'Message'  = 'Successfully read REST API body from stream';
            'Severity' = 'Debug';
            'Area'     = 'RestApi';
        };
        'RestApiBodyReadError' = @{
            'Code'     = 1818;
            'Message'  = 'An error occurred while reading REST API body from stream';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiClientInvalid' = @{
            'Code'     = 1819;
            'Message'  = 'The REST API TCP client provided is invalid.';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiWebPathExpandSuccess' = @{
            'Code'     = 1820;
            'Message'  = 'Successfully expanded REST API web path';
            'Severity' = 'Debug';
            'Area'     = 'RestApi';
        };
        'RestApiWebPathExpandError' = @{
            'Code'     = 1821;
            'Message'  = 'An error occurred while expanding REST API web path';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiQueryStringExpandError' = @{
            'Code'     = 1822;
            'Message'  = 'An error occurred while expanding REST API query string';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiResponseBuildSuccess' = @{
            'Code'     = 1823;
            'Message'  = 'Successfully built REST API response';
            'Severity' = 'Debug';
            'Area'     = 'RestApi';
        };
        'RestApiResponseBuildError' = @{
            'Code'     = 1824;
            'Message'  = 'An error occurred while building REST API response';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'FaviconFileNotFound' = @{
            'Code'     = 1825;
            'Message'  = 'The favicon file was not found';
            'Severity' = 'Warning';
            'Area'     = 'RestApi';
        };
        'RestApiFaviconResponseBuildSuccess' = @{
            'Code'     = 1826;
            'Message'  = 'Successfully built REST API favicon response from file';
            'Severity' = 'Debug';
            'Area'     = 'RestApi';
        };
        'RestApiFaviconResponseBuildError' = @{
            'Code'     = 1827;
            'Message'  = 'An error occurred while building REST API favicon response';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiAccessControlNotDefined' = @{
            'Code'     = 1828;
            'Message'  = 'No access control configuration is defined for the REST API';
            'Severity' = 'Audit';
            'Area'     = 'RestApi';
        };
        'RestApiAccessControlPermissionDenied' = @{
            'Code'     = 1829;
            'Message'  = 'REST API access control permission denied for user';
            'Severity' = 'Audit';
            'Area'     = 'RestApi';
        };
        'RestApiAccessControlPermissionGranted' = @{
            'Code'     = 1830;
            'Message'  = 'REST API access control permission granted for user';
            'Severity' = 'Audit';
            'Area'     = 'RestApi';
        };
        'RestApiAccessControlContentLengthExceeded' = @{
            'Code'     = 1831;
            'Message'  = 'The REST API request content length exceeds the maximum allowed size of bytes for user';
            'Severity' = 'Audit';
            'Area'     = 'RestApi';
        };
        'RestApiAccessControlMethodNotAllowed' = @{
            'Code'     = 1832;
            'Message'  = 'The REST API request method is not allowed';
            'Severity' = 'Audit';
            'Area'     = 'RestApi';
        };
        'RestApiAccessControlOriginNotAllowed' = @{
            'Code'     = 1833;
            'Message'  = 'The REST API request origin is not allowed';
            'Severity' = 'Audit';
            'Area'     = 'RestApi';
        };
        'RestApiSpaceFileEmpty' = @{
            'Code'     = 1834;
            'Message'  = 'The REST API space file is empty';
            'Severity' = 'Warning';
            'Area'     = 'RestApi';
        };
        'RestApiSpaceFileParseError' = @{
            'Code'     = 1835;
            'Message'  = 'An error occurred while parsing the REST API space file';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiSpaceFileParsedSuccessfully' = @{
            'Code'     = 1836;
            'Message'  = 'The REST API space file has been parsed successfully';
            'Severity' = 'Audit';
            'Area'     = 'RestApi';
        };
        'RestApiNoSpacesConfigured' = @{
            'Code'     = 1837;
            'Message'  = 'No REST API spaces are configured';
            'Severity' = 'Warning';
            'Area'     = 'RestApi';
        };
        'RestApiSpaceNotFound' = @{
            'Code'     = 1838;
            'Message'  = 'The specified REST API space was not found';
            'Severity' = 'Warning';
            'Area'     = 'RestApi';
        };
        'RestApiSpaceMissing' = @{
            'Code'     = 1839;
            'Message'  = 'No REST API spaces were provided for building the API path';
            'Severity' = 'Warning';
            'Area'     = 'RestApi';
        };
        'RestApiApiCommandExecutionFieldExists' = @{
            'Code'     = 1840;
            'Message'  = 'The REST API ApiCommandExecution field exists in the API path';
            'Severity' = 'Debug';
            'Area'     = 'RestApi';
        };
        'RestApiApiCommandExecutionFieldNotFound' = @{
            'Code'     = 1841;
            'Message'  = 'The REST API ApiCommandExecution field was not found in the API path';
            'Severity' = 'Debug';
            'Area'     = 'RestApi';
        };
        'RestApiApiCommandExecutionFieldTestError' = @{
            'Code'     = 1842;
            'Message'  = 'An error occurred while testing for the REST API ApiCommandExecution field in the API path';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiMethodNotAllowedForCommandExecution' = @{
            'Code'     = 1843;
            'Message'  = 'The REST API method used is not allowed for API command execution';
            'Severity' = 'Warning';
            'Area'     = 'RestApi';
        };
        'RestApiCommandExecutionInvokingFunction' = @{
            'Code'     = 1844;
            'Message'  = 'Invoking REST API command execution function';
            'Severity' = 'Debug';
            'Area'     = 'RestApi';
        };
        'RestApiCommandExecutionFunctionError' = @{
            'Code'     = 1845;
            'Message'  = 'An error occurred while invoking the REST API command execution function';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiCommandExecutionFunctionErrorNoResponse' = @{
            'Code'     = 1846;
            'Message'  = 'The REST API command execution function is either empty or the command does not exist';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiCommandExecutionError' = @{
            'Code'     = 1847;
            'Message'  = 'An error occurred during REST API command execution';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiCommandExecutionSucceeded' = @{
            'Code'     = 1848;
            'Message'  = 'REST API command execution completed successfully';
            'Severity' = 'Debug';
            'Area'     = 'RestApi';
        };
        'RestApiInvalidPathForCommandExecution' = @{
            'Code'     = 1849;
            'Message'  = 'The REST API path provided for command execution is invalid or too deep';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiNoSpaceInPath' = @{
            'Code'     = 1850;
            'Message'  = 'No REST API space was found in the API path for command execution';
            'Severity' = 'Debug';
            'Area'     = 'RestApi';
        };
        'RestApiRequestFailed' = @{
            'Code'     = 1851;
            'Message'  = 'The REST API request could not be processed successfully';
            'Severity' = 'Error';
            'Area'     = 'RestApi';
        };
        'RestApiRequestSuccessful' = @{
            'Code'     = 1852;
            'Message'  = 'The REST API request has been processed successfully';
            'Severity' = 'Info';
            'Area'     = 'RestApi';
        };
        'NoTlsCertConfigProvided' = @{
            'Code'     = 1900;
            'Message'  = 'No TLS certificate configuration was provided for certificate configuration';
            'Severity' = 'Warning';
            'Area'     = 'Certificate';
        };
        'TlsCertFileNotFound' = @{
            'Code'     = 1901;
            'Message'  = 'The TLS certificate file was not found';
            'Severity' = 'Error';
            'Area'     = 'Certificate';
        };
        'TlsCertConfigCreated' = @{
            'Code'     = 1902;
            'Message'  = 'TLS certificate configuration has been successfully created';
            'Severity' = 'Info';
            'Area'     = 'Certificate';
        };
        'NoTlsCertConfigProvidedForLoader' = @{
            'Code'     = 1903;
            'Message'  = 'No TLS certificate configuration was provided for getting the TLS certificate';
            'Severity' = 'Error';
            'Area'     = 'Certificate';
        };
        'TlsCertLoadFromPathFailed' = @{
            'Code'     = 1904;
            'Message'  = 'Failed to load TLS certificate from path';
            'Severity' = 'Error';
            'Area'     = 'Certificate';
        };
        'TlsCertLoadedFromPath' = @{
            'Code'     = 1905;
            'Message'  = 'TLS certificate has been successfully loaded from path';
            'Severity' = 'Info';
            'Area'     = 'Certificate';
        };
        'TlsCertNotFoundInStore' = @{
            'Code'     = 1906;
            'Message'  = 'The TLS certificate was not found in the certificate store using the provided configuration';
            'Severity' = 'Error';
            'Area'     = 'Certificate';
        };
        'TlsCertLoadedFromStore' = @{
            'Code'     = 1907;
            'Message'  = 'TLS certificate has been successfully loaded from the certificate store';
            'Severity' = 'Info';
            'Area'     = 'Certificate';
        };
        'TlsCertLoadFromStoreFailed' = @{
            'Code'     = 1908;
            'Message'  = 'Failed to load TLS certificate from the certificate store using the provided configuration';
            'Severity' = 'Error';
            'Area'     = 'Certificate';
        };
        'TlsCertLoadFailedUnknownReason' = @{
            'Code'     = 1909;
            'Message'  = 'Failed to load TLS certificate using the provided configuration due to an unknown reason';
            'Severity' = 'Error';
            'Area'     = 'Certificate';
        };
        'AccessControlNoAllowedRestApiMethodsSpecified' = @{
            'Code'     = 2000;
            'Message'  = 'No allowed REST API methods were specified in the access control configuration';
            'Severity' = 'Warning';
            'Area'     = 'AccessControl';
        };
        'AccessControlAllRestApiResourcesBlocked' = @{
            'Code'     = 2001;
            'Message'  = 'All REST API resources are blocked in this access control configuration';
            'Severity' = 'Warning';
            'Area'     = 'AccessControl';
        };
        'AccessControlAllRestApiResourcesAllowed' = @{
            'Code'     = 2002;
            'Message'  = 'All REST API resources are allowed in this access control configuration';
            'Severity' = 'Warning';
            'Area'     = 'AccessControl';
        };
        'AccessControlObjectCreated' = @{
            'Code'     = 2003;
            'Message'  = 'Access control object has been successfully created';
            'Severity' = 'Info';
            'Area'     = 'AccessControl';
        };
        'AccessRoleNoRoleNameProvided' = @{
            'Code'     = 2100;
            'Message'  = 'No access role name was provided for creating the access role';
            'Severity' = 'Error';
            'Area'     = 'AccessRole';
        };
        'AccessRoleNoAccessControlObjectsProvided' = @{
            'Code'     = 2101;
            'Message'  = 'No access control objects were provided for creating the access role';
            'Severity' = 'Error';
            'Area'     = 'AccessRole';
        };
        'AccessRoleNoUsersProvided' = @{
            'Code'     = 2102;
            'Message'  = 'No users were provided for creating the access role. Use "*" to apply the role to all users.';
            'Severity' = 'Error';
            'Area'     = 'AccessRole';
        };
        'AccessRoleFileCreationFailed' = @{
            'Code'     = 2103;
            'Message'  = 'The access role file could not be created';
            'Severity' = 'Error';
            'Area'     = 'AccessRole';
        };
        'AccessRoleCreated' = @{
            'Code'     = 2104;
            'Message'  = 'Access role has been successfully created';
            'Severity' = 'Info';
            'Area'     = 'AccessRole';
        };
        'AccessRoleAlreadyExists' = @{
            'Code'     = 2105;
            'Message'  = 'The access role already exists and cannot be created again. Use -Force to overwrite the existing role';
            'Severity' = 'Error';
            'Area'     = 'AccessRole';
        };
        'AccessRoleFileEmptyContent' = @{
            'Code'     = 2106;
            'Message'  = 'The access role file is empty and could not be parsed';
            'Severity' = 'Error';
            'Area'     = 'AccessRole';
        };
        'AccessRoleFileParseError' = @{
            'Code'     = 2107;
            'Message'  = 'An error occurred while parsing the access role file';
            'Severity' = 'Error';
            'Area'     = 'AccessRole';
        };
        'AccessRoleFileReadSuccess' = @{
            'Code'     = 2108;
            'Message'  = 'Successfully read access role file';
            'Severity' = 'Audit';
            'Area'     = 'AccessRole';
        };
        'AccessRoleFolderNotFound' = @{
            'Code'     = 2109;
            'Message'  = 'The access role folder was not found. Please run the Rest-Api configuration command to create the folder and try again';
            'Severity' = 'Warning';
            'Area'     = 'AccessRole';
        };
        'StringToBoolConversionInvalidValue' = @{
            'Code'     = 4000;
            'Message'  = 'The provided string value could not be converted to a boolean. Assuming false';
            'Severity' = 'Warning';
            'Area'     = 'Tools';
        };
        'ImageToBase64FileNotFound' = @{
            'Code'     = 4001;
            'Message'  = 'The image file to convert to Base64 was not found';
            'Severity' = 'Error';
            'Area'     = 'Tools';
        };
        'ImageToBase64ConversionFailed' = @{
            'Code'     = 4002;
            'Message'  = 'The image file could not be converted to Base64';
            'Severity' = 'Error';
            'Area'     = 'Tools';
        };
        'WebSocketNameEmpty' = @{
            'Code'     = 6000;
            'Message'  = 'The WebSocket name is empty';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketAddressEmpty' = @{
            'Code'     = 6001;
            'Message'  = 'The WebSocket listen address is empty';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketAlreadyOpened' = @{
            'Code'     = 6002;
            'Message'  = 'The WebSocket is already opened';
            'Severity' = 'Warning';
            'Area'     = 'WebSocket';
        };
        'WebSocketCreatedSuccessfully' = @{
            'Code'     = 6003;
            'Message'  = 'The WebSocket has been created successfully';
            'Severity' = 'Info';
            'Area'     = 'WebSocket';
        };
        'WebSocketDisconnectError' = @{
            'Code'     = 6004;
            'Message'  = 'An error occurred while disconnecting the WebSocket. Retrying by simply disposing the WebSocket.';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketDisposeError' = @{
            'Code'     = 6005;
            'Message'  = 'An error occurred while disposing the WebSocket';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketDisconnectedSuccessfully' = @{
            'Code'     = 6006;
            'Message'  = 'The WebSocket has been disconnected and disposed successfully';
            'Severity' = 'Info';
            'Area'     = 'WebSocket';
        };
        'WebSocketDisposedSuccessfully' = @{
            'Code'     = 6007;
            'Message'  = 'The WebSocket has been disposed successfully. A prior disconnect was not successful.';
            'Severity' = 'Warning';
            'Area'     = 'WebSocket';
        };
        'WebSocketNotConnected' = @{
            'Code'     = 6008;
            'Message'  = 'The WebSocket is not connected';
            'Severity' = 'Info';
            'Area'     = 'WebSocket';
        };
        'UpdateWebSocketNameEmpty' = @{
            'Code'     = 6009;
            'Message'  = 'The new WebSocket name is empty';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'UpdateWebSocketClientEmpty' = @{
            'Code'     = 6010;
            'Message'  = 'The WebSocket client to update is empty';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'UpdateWebSocketCancellationTokenSourceEmpty' = @{
            'Code'     = 6011;
            'Message'  = 'The WebSocket cancellation token source to update is empty';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketUpdatedSuccessfully' = @{
            'Code'     = 6012;
            'Message'  = 'The WebSocket has been updated successfully';
            'Severity' = 'Info';
            'Area'     = 'WebSocket';
        };
        'WebSocketWriteError' = @{
            'Code'     = 6013;
            'Message'  = 'An error occurred while writing to the WebSocket';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'NoWebSocketConfigNameProvided' = @{
            'Code'     = 6014;
            'Message'  = 'No WebSocket configuration name was provided for loading the WebSocket';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'NoWebSocketConfigAddressProvided' = @{
            'Code'     = 6015;
            'Message'  = 'No WebSocket configuration address was provided for loading the WebSocket';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketConfigNameAlreadyExists' = @{
            'Code'     = 6016;
            'Message'  = 'The WebSocket configuration name already exists and cannot be created again. Use -Force to overwrite the existing configuration';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketConfigConfiguredSuccessfully' = @{
            'Code'     = 6017;
            'Message'  = 'WebSocket configuration has been successfully created';
            'Severity' = 'Info';
            'Area'     = 'WebSocket';
        };
        'WebSocketConfigNoNameProvided' = @{
            'Code'     = 6018;
            'Message'  = 'No WebSocket configuration name was provided for deleting the WebSocket configuration';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketConfigNotFoundOrEmpty' = @{
            'Code'     = 6019;
            'Message'  = 'The specified WebSocket configuration was not found or is empty';
            'Severity' = 'Warning';
            'Area'     = 'WebSocket';
        };
        'WebSocketConfigCorrupted' = @{
            'Code'     = 6020;
            'Message'  = 'The specified WebSocket configuration is corrupted and could not be parsed';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketConfigMissingNameOrAddress' = @{
            'Code'     = 6021;
            'Message'  = 'The specified WebSocket configuration is missing the name or address';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketConfigLoadedSuccessfully' = @{
            'Code'     = 6022;
            'Message'  = 'WebSocket configuration has been successfully loaded';
            'Severity' = 'Info';
            'Area'     = 'WebSocket';
        };
        'WebSocketNoConfigsFound' = @{
            'Code'     = 6023;
            'Message'  = 'No WebSocket configurations were found';
            'Severity' = 'Warning';
            'Area'     = 'WebSocket';
        };
        'WebSocketHandlerNoNameProvided' = @{
            'Code'     = 6024;
            'Message'  = 'No WebSocket name was provided for handling the WebSocket connection';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketEnvironmentInitializedSuccessfully' = @{
            'Code'     = 6025;
            'Message'  = 'WebSocket environment has been initialized successfully';
            'Severity' = 'Info';
            'Area'     = 'WebSocket';
        };
        'WebSocketReadError' = @{
            'Code'     = 6026;
            'Message'  = 'An error occurred while reading from the WebSocket';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'NoWebSocketConfigProvided' = @{
            'Code'     = 6027;
            'Message'  = 'No WebSocket configuration was provided for handling the WebSocket connection';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketConfigReadFailed' = @{
            'Code'     = 6028;
            'Message'  = 'Failed to read the WebSocket configuration for handling the WebSocket connection';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketMessageAddQueueWebSocketNameMissing' = @{
            'Code'     = 6029;
            'Message'  = 'No WebSocket name was provided for adding the message to the WebSocket message queue';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'WebSocketMessageAddQueueMessageMissing' = @{
            'Code'     = 6030;
            'Message'  = 'No message was provided for adding to the WebSocket message queue';
            'Severity' = 'Error';
            'Area'     = 'WebSocket';
        };
        'ImageMimeTypeFileNotFound' = @{
            'Code'     = 4003;
            'Message'  = 'The image file to get MIME type was not found';
            'Severity' = 'Error';
            'Area'     = 'Tools';
        };
        'IcingaUnitInvalidInputValue' = @{
            'Code'     = 4100;
            'Message'  = 'The provided input value is not a valid "<number><unit>" value and could not be converted';
            'Severity' = 'Error';
            'Area'     = 'Tools';
        };
        'IcingaUnitMissingInputUnit' = @{
            'Code'     = 4101;
            'Message'  = 'No input unit could be determined for the conversion. Provide a unit suffix on the value or use -InputUnit';
            'Severity' = 'Error';
            'Area'     = 'Tools';
        };
        'IcingaUnitUnknownUnit' = @{
            'Code'     = 4102;
            'Message'  = 'The provided input or target unit is not a known unit for the conversion';
            'Severity' = 'Error';
            'Area'     = 'Tools';
        };
        'IcingaUnitFamilyMismatch' = @{
            'Code'     = 4103;
            'Message'  = 'The target unit belongs to a different unit family than the input unit and cannot be converted';
            'Severity' = 'Error';
            'Area'     = 'Tools';
        };
        'IcingaUnitConverted' = @{
            'Code'     = 4150;
            'Message'  = 'The unit conversion completed successfully';
            'Severity' = 'Debug';
            'Area'     = 'Tools';
        };
        'WindowsInformationClassUnknown' = @{
            'Code'        = 4200;
            'Message'     = 'The requested CIM class does not exist on this system';
            'Severity'    = 'Debug';
            'Area'        = 'Tools';
            'Description' = 'Optional classes such as MPIO_DISK_INFO are probed on purpose, so this is only logged at Debug level; plugins surface the error in their output';
        };
        'WindowsInformationNamespaceInvalid' = @{
            'Code'        = 4201;
            'Message'     = 'The requested CIM namespace does not exist on this system';
            'Severity'    = 'Debug';
            'Area'        = 'Tools';
            'Description' = 'Optional namespaces are probed on purpose, so this is only logged at Debug level; plugins surface the error in their output';
        };
        'WindowsInformationAccessDenied' = @{
            'Code'        = 4202;
            'Message'     = 'Access to the requested CIM class was denied';
            'Severity'    = 'Error';
            'Area'        = 'Tools';
            'Description' = 'The user running the check needs the "Enable Account" and "Remote Enable" WMI permissions on the namespace, for example through the "Remote Management Users" group';
        };
        'WindowsInformationInvalidQuery' = @{
            'Code'     = 4203;
            'Message'  = 'The CIM query is invalid, check the filter and the requested properties';
            'Severity' = 'Error';
            'Area'     = 'Tools';
        };
        'WindowsInformationQueryFailed' = @{
            'Code'     = 4204;
            'Message'  = 'The CIM query failed with an unhandled error';
            'Severity' = 'Error';
            'Area'     = 'Tools';
        };
        'WindowsInformationClassNameMissing' = @{
            'Code'     = 4205;
            'Message'  = 'No CIM class name was provided for the query';
            'Severity' = 'Error';
            'Area'     = 'Tools';
        };
        'WindowsInformationQueried' = @{
            'Code'     = 4210;
            'Message'  = 'The CIM query completed successfully';
            'Severity' = 'Debug';
            'Area'     = 'Tools';
        };
        'ArrayFilterInvalidPattern' = @{
            'Code'     = 4250;
            'Message'  = 'A filter pattern is no valid wildcard expression, the value is treated as not matching';
            'Severity' = 'Warning';
            'Area'     = 'Tools';
        };
        'ScheduledTaskQueryFailed' = @{
            'Code'     = 4600;
            'Message'  = 'The scheduled tasks could not be queried';
            'Severity' = 'Error';
            'Area'     = 'Provider';
        };
        'ScheduledTaskInformationCollected' = @{
            'Code'     = 4650;
            'Message'  = 'The scheduled task information was collected successfully';
            'Severity' = 'Debug';
            'Area'     = 'Provider';
        };
        'WebUIAssetPathEmpty' = @{
            'Code'     = 13000;
            'Message'  = 'No Web UI asset path was provided for retrieving the Web UI asset';
            'Severity' = 'Error';
            'Area'     = 'WebUI';
        };
        'WebUIRequestPathInvalid' = @{
            'Code'     = 13001;
            'Message'  = 'The Web UI request path is invalid for retrieving the Web UI asset';
            'Severity' = 'Error';
            'Area'     = 'WebUI';
        };
        'WebUIPathTraversalDetected' = @{
            'Code'     = 13002;
            'Message'  = 'A path traversal attempt was detected in the Web UI request path for retrieving the Web UI asset';
            'Severity' = 'Error';
            'Area'     = 'WebUI';
        };
        'IcingaClientConnected' = @{
            'Code'     = 50000;
            'Message'  = 'We are already connected to the Icinga node';
            'Severity' = 'Info';
            'Area'     = 'IcingaProtocol';
        };
        'IcingaClientCreated' = @{
            'Code'     = 50001;
            'Message'  = 'We have established a new connection to Icinga node';
            'Severity' = 'Info';
            'Area'     = 'IcingaProtocol';
        };
        'IcingaAddressInvalid' = @{
            'Code'     = 50002;
            'Message'  = 'We tried to use an address for connecting to an Icinga node, but the address was empty';
            'Severity' = 'Error';
            'Area'     = 'IcingaProtocol';
        };
        'IcingaClientReplaced' = @{
            'Code'     = 50003;
            'Message'  = 'The Icinga node with the mentioned address has been replaced with a new connection';
            'Severity' = 'Info';
            'Area'     = 'IcingaProtocol';
        };
        'IcingaClientAdded' = @{
            'Code'     = 50004;
            'Message'  = 'Added a new known Icinga endpoint to our connection pool';
            'Severity' = 'Info';
            'Area'     = 'IcingaProtocol';
        };
        'IcingaClientAddingFailed' = @{
            'Code'     = 50005;
            'Message'  = 'Adding the Icinga client object failed as either the address or the client was invalid';
            'Severity' = 'Error';
            'Area'     = 'IcingaProtocol';
        };
        'IcingaClientRPCMessageNull' = @{
            'Code'     = 50006;
            'Message'  = 'The provided RPC message for enqueuing is null or empty';
            'Severity' = 'Warning';
            'Area'     = 'IcingaProtocol';
        };
        'IcingaClientCertificateFileNotFound' = @{
            'Code'        = 50007;
            'Message'     = 'The Icinga Protocol client certificate file was not found';
            'Severity'    = 'Error';
            'Area'        = 'IcingaProtocol';
            'Description' = 'The Icinga Agent certificate file was not found at the specified path. Please ensure you have placed the certificate with the correct name and that the Icinga for Windows service has the necessary permissions to access it. The specified hostname in your Icinga Protocol configuration should match the certificate filename, without the .pfx extension.';
        };
        'IcingaClientRPCMessageParseError' = @{
            'Code'     = 50008;
            'Message'  = 'An error occurred while parsing the RPC message for enqueuing';
            'Severity' = 'Error';
            'Area'     = 'IcingaProtocol';
        };
        'IcingaCertCommonNameMissing' = @{
            'Code'        = 50009;
            'Message'     = 'No common name was provided for the self-signed certificate';
            'Severity'    = 'Error';
            'Area'        = 'IcingaProtocol';
            'Description' = 'No common name was provided for the self-signed certificate. You must provide a common name when generating a self-signed certificate.';
        };
        'IcingaCertStoredLocally' = @{
            'Code'        = 50010;
            'Message'     = 'The self-signed certificate has been successfully stored locally';
            'Severity'    = 'Info';
            'Area'        = 'IcingaProtocol';
            'Description' = 'The self-signed certificate has been successfully stored locally. You can now use this certificate with Icinga for Windows to establish a secure connection to Icinga nodes.';
        };
        'IcingaCertStoredCertStore' = @{
            'Code'        = 50011;
            'Message'     = 'The self-signed certificate has been successfully stored in the Windows certificate store';
            'Severity'    = 'Info';
            'Area'        = 'IcingaProtocol';
            'Description' = 'The self-signed certificate has been successfully stored in the Windows certificate store.';
        };
        'IcingaCertMissingForMerge' = @{
            'Code'        = 50012;
            'Message'     = 'The Icinga Protocol certificate file was not found';
            'Severity'    = 'Error';
            'Area'        = 'IcingaProtocol';
            'Description' = 'The Icinga Protocol certificate file was not found at the specified path. Please ensure you have placed the certificate with the correct name and that the Icinga for Windows service has the necessary permissions to access it. The specified hostname in your Icinga Protocol configuration should match the certificate filename, without the .pfx extension.';
        };
        'IcingaCAImportPathNotfound' = @{
            'Code'        = 50013;
            'Message'     = 'The Icinga CA file to import was not found at the specified path';
            'Severity'    = 'Error';
            'Area'        = 'IcingaProtocol';
            'Description' = 'The Icinga CA file was not found at the specified path. Please ensure you have placed the certificate with the correct name and that the Icinga for Windows service has the necessary permissions to access it.';
        };
        'IcingaCAContentIsEmpty' = @{
            'Code'        = 50014;
            'Message'     = 'The Icinga CA content to import is empty';
            'Severity'    = 'Error';
            'Area'        = 'IcingaProtocol';
            'Description' = 'The Icinga CA content to import is empty. Please ensure you have provided a valid Icinga CA file.';
        };
        'IcingaEndpointsEmpty' = @{
            'Code'        = 50015;
            'Message'     = 'The Icinga endpoints to connect to are empty';
            'Severity'    = 'Error';
            'Area'        = 'IcingaProtocol';
            'Description' = 'The Icinga endpoints to connect to are empty. Please ensure you have provided at least one Icinga endpoint.';
        };
        'IcingaZoneNameNotDefined' = @{
            'Code'        = 50016;
            'Message'     = 'The Icinga zone name is undefined';
            'Severity'    = 'Error';
            'Area'        = 'IcingaProtocol';
            'Description' = 'The Icinga zone name is undefined. Please ensure you have provided a valid Icinga zone name.';
        };
        'IcingaHostnameNotDefined' = @{
            'Code'        = 50017;
            'Message'     = 'The Icinga hostname is not defined';
            'Severity'    = 'Error';
            'Area'        = 'IcingaProtocol';
            'Description' = 'The Icinga hostname is not defined. Please ensure you have provided a valid Icinga hostname.';
        };
        'IcingaTlsCertConfigMissing' = @{
            'Code'        = 50018;
            'Message'     = 'The Icinga TLS certificate config is not defined';
            'Severity'    = 'Error';
            'Area'        = 'IcingaProtocol';
            'Description' = 'The Icinga TLS certificate config is not defined. Please ensure you have provided a valid Icinga TLS certificate config.';
        };
        'IcingaProtoclConfigWritten' = @{
            'Code'        = 50019;
            'Message'     = 'The Icinga Protocol configuration has been successfully written to disk';
            'Severity'    = 'Info';
            'Area'        = 'IcingaProtocol';
            'Description' = 'The Icinga Protocol configuration has been successfully written to disk.';
        };
    };
}
