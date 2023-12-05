param(
    # Option to make development more friendly. Increases log level, reloads session-cached code, etc.
    [switch]$developerMode,
    # Option to run this script synchronously in the current shell. By default it runs in the background.
    [switch]$runSynchronous
)

# Setup logging and config
Import-Module $PSScriptRoot\..\modules\Logger.psm1
try {
    $appconfig = Get-Content $PSScriptRoot\..\config.json | ConvertFrom-Json
} catch {
    Write-PSFMessage -Level Critical "Unable to load app config json" -ErrorRecord $_
    exit
}
if ($appconfig.log_level) {
    Logger\SetLogLevel -logLevel $appconfig.log_level
    # Set the console output log level to the same as the actual log level for developers running synchronously
    if ($developerMode -and $runSynchronous) {
        Logger\OutputToConsole -logLevel $appconfig.log_level
    }
}

# Since pre-commands in sunshine are synchronous, by default we'll launch this script again in another hidden powershell process
if (-not $runSynchronous) {
    $arguments = @()
    # To recompile session-cached C# files for developers, we reload via running this script with -ExecutionPolicy Bypass
    if ($developerMode) { $arguments += "-ExecutionPolicy Bypass" } else { $arguments += "-ExecutionPolicy RemoteSigned" }
    $arguments += "-File `"$($PSCommandPath)`""
    $arguments += $($args)
    $arguments += "-runSynchronous"
    if ($developerMode) { $arguments += "-developerMode" }
    Start-Process powershell.exe -NoNewWindow -ArgumentList "$([string]$arguments)"
    if ($appconfig.stream_start_delay -gt 0) {
        Start-Sleep -Seconds $appconfig.stream_start_delay
    }
    exit
}

# Only allow one instance of this script- if one is already running, exit.
$mutex = New-Object System.Threading.Mutex($false, "SunshineAutomationSuite")
if (-not $mutex.WaitOne(0)) {
    Write-PSFMessage -Level Host -Message "Another instance of the script is already running. Exiting..."
    exit
}

try {
    # Since modules are otherwise tied to a powershell session, we reload the module fresh so a developer need not reload their session after a module level code 
    # IMPORTANT: This will not recompile C#- for that, -ExecutionPolicy Bypass is required
    if ($developerMode) { Get-Module DisplayManager | Remove-Module }
    Import-Module $PSScriptRoot\..\modules\StreamEventHelper.psm1
    Set-Location $PSScriptRoot

    # Load and validate application settings
    $settings = Get-Content -Path $PSScriptRoot\..\..\settings\settings.json | ConvertFrom-Json
    if (-not $settings.monitors -or @($settings.monitors).Length -eq 0) {
        Write-PSFMessage -Level Critical -Message "Empty or nonexistent monitor list in settings- exiting..."
        exit
    }
    $settingsPrimaryMonitorCount = 0
    foreach ($monitor in $settings.monitors) {
        if (-not $monitor.id -or -not ($monitor.id -is "int")) {
            Write-PSFMessage -Level Critical -Message "Invalid or missing id value for monitor name $($monitor.name)- exiting..."
            exit
        }
        if ($monitor.resolution_while_streaming -and -not (@("NO_CHANGE","DISABLE_MONITOR","SYNC_RESOLUTION_TO_CLIENT","CUSTOM") -contains $monitor.resolution_while_streaming)) { 
            Write-PSFMessage -Level Critical -Message "Invalid resolution_while_streaming value for monitor name $($monitor.name)- exiting..."
            exit
        }
        if ($monitor.hdr_while_streaming -and -not (@("NO_CHANGE","SYNC_HDR_TO_CLIENT","ENABLE","DISABLE") -contains $monitor.hdr_while_streaming)) { 
            Write-PSFMessage -Level Critical -Message "Invalid hdr_while_streaming value for monitor name $($monitor.name)- exiting..."
            exit
        }
        if ($monitor.primary_while_streaming) {
            if (-not ($monitor.primary_while_streaming -is "boolean")) { 
                Write-PSFMessage -Level Critical -Message "Invalid primary_while_streaming value for monitor name $($monitor.name)- exiting..."
                exit
            }
            $settingsPrimaryMonitorCount += 1
        }
    }
    if ($settingsPrimaryMonitorCount -gt 1) {
        Write-PSFMessage -Level Critical -Message "Found $settingsPrimaryMonitorCount monitors with primary_while_streaming true. Only one monitor can be primary- exiting..."
        exit
    }

    # Update graphics settings
    Write-PSFMessage -Level Verbose -Message "Stream started- updating applicable graphics settings..."
    StreamEventHelper\StartStreamingSession -settings $settings
    Write-PSFMessage -Level Verbose -Message "Applicable graphics settings update complete after stream start."

    # Create simple keep alive listener pipe which allows other powershell scripts to end this process by connecting to it
    $keepAlivePipeName = "SunshineAutomationSuite-KeepAlive"
    Remove-Item "\\.\pipe\$keepAlivePipeName" -ErrorAction Ignore
    $keepAliveServerStream = New-Object System.IO.Pipes.NamedPipeServerStream($keepAlivePipeName, [System.IO.Pipes.PipeDirection]::In, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous)
    $keepAliveConnection = $keepAliveServerStream.WaitForConnectionAsync()

    # Wait for stream to be either manually quit by user or have not been streaming for longer than a configured grace period
    Write-PSFMessage -Level Verbose -Message "Waiting for sunshine session to end..."
    $attemptsSinceLastLog = 0
    $lastStreamed = Get-Date
    do {
        $pollingIntervalSecs = if ($appconfig.stream_polling_interval) {$appconfig.stream_polling_interval} else {2}
        if ($null -ne (Get-Process sunshine -ErrorAction SilentlyContinue) -and $null -ne (Get-NetUDPEndpoint -OwningProcess (Get-Process sunshine).Id -ErrorAction Ignore)) {
            $lastStreamed = Get-Date
        }
        if ($attemptsSinceLastLog * $pollingIntervalSecs -ge 300) {
            Write-PSFMessage -Level Debug -Message "Still waiting for sunshine session to end..."
            $attemptsSinceLastLog = 0
        }
        $attemptsSinceLastLog += 1
        Start-Sleep -Seconds $pollingIntervalSecs
    } until ($keepAliveConnection.IsCompleted -or (((Get-Date) - $lastStreamed).TotalSeconds -gt $appconfig.stream_end_grace_period))
    Write-PSFMessage -Level Debug -Message "$(
            if ($keepAliveConnection.IsCompleted) {"Stream quit by user"}
            else {"Sunshine has not been streaming for more than $($appconfig.stream_end_grace_period) seconds- considering stream as quit"}
        )"

    # Revert graphics settings after stream has ended
    Write-PSFMessage -Level Verbose -Message "Stream ended- reverting applicable graphics settings to original state..."
    StreamEventHelper\CompleteStreamingSession
    Write-PSFMessage -Level Verbose -Message "Applicable graphics settings reversion complete after stream end."
}
catch {
    Write-PSFMessage -Level Critical -Message "Unhandled exception" -ErrorRecord $_
}
finally {
    if ( $keepAliveServerStream ) { $keepAliveServerStream.Dispose() }
    Wait-PSFMessage
    $mutex.ReleaseMutex()
}
