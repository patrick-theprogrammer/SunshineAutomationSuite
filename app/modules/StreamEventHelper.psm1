Import-Module $PSScriptRoot\DisplayManager\DisplayManager.psd1

$streamStartDisplayStates = @()

function StartStreamingSession($appconfig, $settings) {
    $allDisplays = DisplayManager_GetAllPotentialDisplays
    $enabledDisplays = @()
    foreach ($display in $allDisplays) { if ($display.Enabled) { $enabledDisplays += $display } }
    Write-PSFMessage -Level Debug -Message "Enabled display states before stream start monitor update:"
    foreach ($display in $enabledDisplays) { Write-PSFMessage -Level Debug -Message $($display.ToTableString()) }

    $script:streamStartDisplayStates = @()
    $enabledDisplays | ForEach-Object { $script:streamStartDisplayStates += [PSCustomObject]$_ }

    # First, enable any monitors and then set primary as needed
    foreach ($monitor in $settings.monitors) {
        if (($monitor.resolution_while_streaming -ne "DISABLE_MONITOR") -or $monitor.primary_while_streaming) {
            $displayToUpdate = $null
            # Update the existing enabled display connected to the target if there is one, else the first available display source
            foreach ($display in $allDisplays) {
                if (($null -ne $monitor.id) -and ($display.Target.Id -eq $monitor.id)) {
                    $displayToUpdate = $display
                    break
                }
            }
            if (-not $displayToUpdate) {
                foreach ($display in $allDisplays) {
                    if ((-not $displayToUpdate) -and ($display.Enabled -eq $false)) { 
                        $displayToUpdate = $display
                        break
                    }
                }
            }
            if (-not $displayToUpdate) {
                Write-PSFMessage -Level Warning -Message "No available display source found to enable for monitor $($monitor.name) from settings- are there open outputs on your host device?"
                continue
            }

            if ($displayToUpdate.Enable($monitor.id)) {
                # Refresh target info and set primary if required after successful enable
                $displayToUpdate = DisplayManager_GetRefreshedDisplay -display $displayToUpdate
                if ($monitor.primary_while_streaming) {
                    [void](DisplayManager_SetPrimaryDisplay -display $displayToUpdate)
                }
            }
        }
    }

    # Enabling and setting primary for displays may effect source -> target mapping. Refresh the active displays so that everything is accurate
    $enabledDisplays = DisplayManager_GetEnabledDisplays

    # Then, set graphics settings or disable as needed
    foreach ($monitor in $settings.monitors) {
        $displayToUpdate = $null
        foreach ($enabledDisplay in $enabledDisplays) {
            if (($null -ne $monitor.id) -and ($enabledDisplay.Target.Id -eq $monitor.id)) {
                $displayToUpdate = $enabledDisplay
                break
            }
        }
        if (-not $displayToUpdate) {
            Write-PSFMessage -Level Debug -Message "No enabled display found to update for monitor $($monitor.name) from settings- maybe refresh monitor settings"
            continue
        }
        # Handle Resolution/Enablement
        if ($null -ne $monitor.resolution_while_streaming) {
            switch ($monitor.resolution_while_streaming) {
                "DISABLE_MONITOR" {
                    [void]($displayToUpdate.Disable())
                    break
                }
                "SYNC_RESOLUTION_TO_CLIENT" {
                    if ($null -eq $env:SUNSHINE_CLIENT_WIDTH -or $null -eq $env:SUNSHINE_CLIENT_HEIGHT) {
                        Write-PSFMessage -Level Warning "Unable to sync resolution to sunshine client- could not to find client resolution setting"
                        break
                    }
                    elseif ($null -eq $env:SUNSHINE_CLIENT_FPS) {
                        Write-PSFMessage -Level Debug "Unable to sync refresh rate to sunshine client- could not to find client refresh rate setting"
                    }
                    # If we fail to set resolution with refresh rate, at least still try width x height
                    $displayToUpdate.SetResolution($env:SUNSHINE_CLIENT_WIDTH, $env:SUNSHINE_CLIENT_HEIGHT, $env:SUNSHINE_CLIENT_FPS) `
                        -or $displayToUpdate.SetResolution($env:SUNSHINE_CLIENT_WIDTH, $env:SUNSHINE_CLIENT_HEIGHT)
                    break
                }
                "CUSTOM" {
                    $customResolution = $monitor.custom_resolution_while_streaming
                    if (-not $customResolution) { 
                        Write-PSFMessage -Level Warning "Invalid custom_resolution_while_streaming setting for monitor $($monitor.name), ignoring"
                        break
                    }
                    $displayToUpdate.SetResolution($customResolution.width, $customResolution.height, $customResolution.refresh_rate) `
                        -or $displayToUpdate.SetResolution($customResolution.width, $customResolution.height)
                    break
                }
                "NO_CHANGE" { break }
                default {
                    Write-PSFMessage -Level Verbose -Message "Invalid resolution_while_streaming value $($monitor.resolution_while_streaming) for monitor $($monitor.name)- assuming NO_CHANGE behavior"
                    break
                }
            }
        }
        # Handle HDR
        if ($null -ne $monitor.hdr_while_streaming) {
            switch ($monitor.hdr_while_streaming) {
                "SYNC_HDR_TO_CLIENT" {
                    if ($null -eq $env:SUNSHINE_CLIENT_HDR) {
                        Write-PSFMessage -Level Warning "Unable to sync hdr to sunshine client- could not to find client hdr setting"
                        break
                    }
                    if ($env:SUNSHINE_CLIENT_HDR -eq $true) { [void]($displayToUpdate.EnableHdr()) }
                    else { [void]($displayToUpdate.DisableHdr()) }
                    break
                }
                "NO_CHANGE" { break }
                default {
                    Write-PSFMessage -Level Verbose -Message "Invalid hdr_while_streaming value $($settings.hdr_while_streaming)- assuming NO_CHANGE behavior"
                    break
                }
            }
        }
    }

    Write-PSFMessage -Level Debug -Message "Enabled display states after stream start monitor update:"
    # We may have disabled some displays in the last step- filter those out
    foreach ($display in $enabledDisplays) { if ($display.Enabled) { Write-PSFMessage -Level Debug -Message $($display.ToTableString()) } }
}

function CompleteStreamingSession($appconfig) {
    # Revert monitor resolutions/enablements/etc
    if (-not $script:streamStartDisplayStates -or $script:streamStartDisplayStates.Count -eq 0) {
        Write-PSFMessage -Level Warning -Message "Unable to complete streaming session- no stream start display states found to revert to"
        return $false
    }

    if (-not (DisplayManager_UpdateDisplaysToStates -displayStates $script:streamStartDisplayStates)) {
        Write-PSFMessage -Level Critical -Message "Error reverting one or more necessary monitor settings after game stream ended"
        return $false           
    }
    # Wait a short time and double check everything was updated correctly
    Start-Sleep -Milliseconds 500
    if (-not (DisplayManager_CurrentDisplaysAreSameAsStates -displayStates $script:streamStartDisplayStates)) {
        Write-PSFMessage -Level Warning -Message "Unable to validate that all display settings were reverted correctly after game stream ended"
        return $false
    }
}
