# Setup logging and config
Import-Module $PSScriptRoot\..\modules\Logger.psm1
try {
    $appconfig = Get-Content $PSScriptRoot\..\config.json | ConvertFrom-Json
} catch {
    Write-PSFMessage -Level Critical "Unable to load app config json" -ErrorRecord $_
    exit
}
if ($appconfig.log_level) {
    [void](Logger\SetLogLevel -logLevelString $appconfig.log_level)
}

# Try to overwrite monitor settings based on currently enabled displays
try {
    Write-PSFMessage -Level Verbose -Message "--------Refreshing monitor settings..."
    Import-Module $PSScriptRoot\..\modules\DisplayManager\DisplayManager.psd1
    $settings = Get-Content -Path $PSScriptRoot\..\..\settings\settings.json | ConvertFrom-Json

    $enabledDisplays = DisplayManager_GetEnabledDisplays
    Write-PSFMessage -Level Debug -Message "Currently enabled displays:"
    $newMonitorsList = @()
    foreach ($display in $enabledDisplays) {
        if (-not $display.Target.Id) { continue }
        Write-PSFMessage -Level Debug -Message $($display.ToTableString())

        $newMonitorSetting = @{
            id = $display.Target.Id
            name = $display.Target.FriendlyName
            hdr_while_streaming = "NO_CHANGE"
            resolution_while_streaming = "NO_CHANGE"
        }
        # Merge in any existing user settings data for each active display
        foreach ($monitor in @($settings.monitors)) {
            if (($null -ne $monitor.id) -and ($monitor.id -eq $display.Target.Id)) {
                if ($null -ne $monitor.hdr_while_streaming) { $newMonitorSetting.hdr_while_streaming = $monitor.hdr_while_streaming }
                if ($null -ne $monitor.resolution_while_streaming) { $newMonitorSetting.resolution_while_streaming = $monitor.resolution_while_streaming }
                if ($null -ne $monitor.primary_while_streaming) { $newMonitorSetting.primary_while_streaming = $monitor.primary_while_streaming }
                break
            }
        }
        $newMonitorsList += $newMonitorSetting
    }
    $settings.monitors = $newMonitorsList

    $settings | ConvertTo-Json | Set-Content -Path $PSScriptRoot\..\..\settings\settings.json
    Write-PSFMessage -Level Verbose -Message "Monitor settings refreshed successfully."
    Write-Host -Level Verbose -Message "Monitor settings refreshed successfully."
} catch {
    Write-PSFMessage -Level Critical -Message "Unhandled exception when refreshing monitor settings:" -ErrorRecord $_
}