$keepAliveName = "SunshineAutomationSuite-KeepAlive"

# Setup logging and config
Import-Module $PSScriptRoot\..\modules\Logger.psm1
try {
    $appconfig = Get-Content $PSScriptRoot\..\config.json | ConvertFrom-Json
}
catch {
    Write-PSFMessage -Level Critical "Unable to load app config json" -ErrorRecord $_
    exit
}
if ($appconfig.log_level) {
    Logger\SetLogLevel -logLevel $appconfig.log_level
}

# If the keep alive doesn't exist (ie there is nothing to quit), continue gracefully.
$activeKeepAliveStreams = Get-ChildItem -Path "\\.\pipe\" | Where-Object { $_.Name -eq $keepAliveName }
if ($activeKeepAliveStreams.Length -eq 0) {
    Write-PSFMessage -Level Verbose -Message "Script is not running- nothing to quit"
    exit
}

$keepAliveClientStream = New-Object System.IO.Pipes.NamedPipeClientStream(".", $keepAliveName, [System.IO.Pipes.PipeDirection]::Out)
try {
    # Connecting to the keep alive stream indicates explicitly that the sunshine session ended
    $keepAliveClientStream.Connect(10000) # 10 second timeout
}
catch {
    # The job will automatically terminate itself after a certain time if there is no active stream, so it's ok for us to fail explicitly killing it
    Write-PSFMessage -Level Warning "Error connecting to keep alive to kill script" -ErrorRecord $_
}
finally {
    $keepAliveClientStream.Dispose()
}