$logProviderName = "SunshineAutomationSuite-Logs"
$logHeaders = 'Timestamp', 'Runspace', 'FunctionName', 'Line', 'Level', 'Message'
$loggingParams = @{
    Name             = "logfile"
    InstanceName     = $logProviderName
    MutexName        = $logProviderName
    FilePath         = "$(Split-Path -Parent $PSScriptRoot)\logs\logs-%date%.log"
    LogRotatePath    = "$(Split-Path -Parent $PSScriptRoot)\logs\logs-*.log"
    LogRetentionTime = "7d"
    FileType         = "CSV"
    CsvDelimiter     = "|"
    IncludeHeader    = $true
    Headers          = $logHeaders
    Enabled          = $true
    Wait             = $true
}
Set-PSFLoggingProvider @loggingParams

$logLevelMap = @{
    Error   = 1
    Warning = 666
    Info    = 5
    Debug   = 8
}
function SetLogLevel($logLevelString) {
    if ($logLevelMap.ContainsKey($logLevelString)) {
        Set-PSFLoggingProvider -Name "logfile" -InstanceName $logProviderName -MaxLevel $logLevelMap[$logLevelString]
    } else {
        Write-PSFMessage "Invalid log level setting `"$logLevelString`""
    }
}

# Use with caution: this will also increase log levels of any other of the user's PSFramework apps on the machine while this app runs
function OutputToConsole($logLevelString) {
    if ($logLevelMap.ContainsKey($logLevelString)) {
        Set-PSFConfig -FullName PSFramework.Message.Info.Maximum -Value $logLevelMap[$logLevelString]
    }
}
