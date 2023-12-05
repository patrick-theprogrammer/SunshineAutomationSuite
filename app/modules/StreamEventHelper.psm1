Import-Module $PSScriptRoot\WindowsDisplayManager\WindowsDisplayManager.psd1

$streamStartDisplayStates = @()
$maxDisplayUpdateAttempts = 3

function StartStreamingSession($settings) {
    $script:streamStartDisplayStates = @()
    WindowsDisplayManager\GetEnabledDisplays | ForEach-Object { $script:streamStartDisplayStates += [PSCustomObject]$_ }

    $targetDisplayStates = @()
    foreach ($monitor in $settings.monitors) {
        $targetDisplayState = @{
            Description = $monitor.Name
            Target = @{ Id = $monitor.Id }
            Enabled = (($monitor.resolution_while_streaming -ne "DISABLE_MONITOR") -or $monitor.primary_while_streaming)
        }
        if ($null -ne $monitor.primary_while_streaming) { $targetDisplayState.Primary = $monitor.primary_while_streaming }

        # Add resolution details
        if ($monitor.resolution_while_streaming -ne "DISABLE_MONITOR") {
            switch ($monitor.resolution_while_streaming) {
                "SYNC_RESOLUTION_TO_CLIENT" {
                    if ((-not $env:SUNSHINE_CLIENT_WIDTH) -or (-not $env:SUNSHINE_CLIENT_HEIGHT)) {
                        Write-PSFMessage -Level Warning "Unable to sync resolution to sunshine client- could not to find client resolution setting"
                        break
                    }
                    $targetDisplayState.Resolution = @{
                        Width = $env:SUNSHINE_CLIENT_WIDTH
                        Height = $env:SUNSHINE_CLIENT_HEIGHT
                    }
                    if ( $env:SUNSHINE_CLIENT_FPS ) { $targetDisplayState.Resolution.RefreshRate = $env:SUNSHINE_CLIENT_FPS }
                    else { Write-PSFMessage -Level Debug "Unable to sync refresh rate to sunshine client- could not to find client refresh rate setting" }
                    break
                }
                "CUSTOM" {
                    $customResolution = $monitor.custom_resolution_while_streaming
                    if (-not ($customResolution.width -is "int" -or $customResolution.height -is "int")) { 
                        Write-PSFMessage -Level Warning "Invalid custom_resolution_while_streaming setting for monitor $($monitor.name), ignoring"
                        break
                    }
                    $targetDisplayState.Resolution = @{
                        Width = $customResolution.width
                        Height = $customResolution.height
                    }
                    if ( $customResolution.refresh_rate -is "int" ) { $targetDisplayState.Resolution.RefreshRate = $customResolution.refresh_rate }
                    break
                }
                "NO_CHANGE" { break }
                default {
                    Write-PSFMessage -Level Warning -Message "Unimplemented resolution_while_streaming value $($monitor.resolution_while_streaming) for monitor $($monitor.name)- assuming NO_CHANGE behavior"
                    break
                }
            }
        }
        # Add HDR details
        if ($null -ne $monitor.hdr_while_streaming) {
            switch ($monitor.hdr_while_streaming) {
                "SYNC_HDR_TO_CLIENT" {
                    if ($null -eq $env:SUNSHINE_CLIENT_HDR) {
                        Write-PSFMessage -Level Warning "Unable to sync hdr to sunshine client- could not to find client hdr setting"
                        break
                    }
                    $targetDisplayState.HdrInfo = @{ HdrEnabled = $env:SUNSHINE_CLIENT_HDR }
                    break
                }
                "ENABLE" {
                    $targetDisplayState.HdrInfo = @{ HdrEnabled = $true }
                    break
                }
                "DISABLE" {
                    $targetDisplayState.HdrInfo = @{ HdrEnabled = $false }
                    break
                }
                "NO_CHANGE" { break }
                default {
                    Write-PSFMessage -Level Warning -Message "Unimplemented hdr_while_streaming value $($settings.hdr_while_streaming) for monitor $($monitor.name)- assuming NO_CHANGE behavior"
                    break
                }
            }
        }
        $targetDisplayStates += $targetDisplayState
    }

    for ($attempt = 0; $attempt -lt $maxDisplayUpdateAttempts; $attempt++) {
        if (WindowsDisplayManager\UpdateDisplaysToStates -validate -displayStates $targetDisplayStates) { return }
        Write-PSFMessage -Level Debug -Message "Issue setting one or more necessary monitor settings after game stream started- trying again..."
    }
    Write-PSFMessage -Level Critical -Message "Max attempts exceeded trying to update monitors after game stream started"
}

function CompleteStreamingSession() {
    if ($null -eq $script:streamStartDisplayStates) {
        Write-PSFMessage -Level Warning -Message "Unable to complete streaming session- no stream start display states found to revert to"
        return
    }

    for ($attempt = 0; $attempt -lt $maxDisplayUpdateAttempts; $attempt++) {
        if (WindowsDisplayManager\UpdateDisplaysToStates -disableNotSpecifiedDisplays -validate -displayStates $script:streamStartDisplayStates) { return }
        Write-PSFMessage -Level Debug -Message "Error setting one or more necessary monitor settings after game stream ended- trying again..."
    }
    Write-PSFMessage -Level Critical -Message "Max attempts exceeded trying to update monitors after game stream ended"
}
