$maxNbrDisplaysSupported = 100

function GetAllPotentialDisplays() {
    # Loop through all display devices by index starting at 0 until no display is returned
    $displays = @()
    for ($i = 0; $i -lt $maxNbrDisplaysSupported; $i++) {
        $display = _GetDisplay($i)
        # If there is no display at index i, we can assume there are only i-1 displays in the system
        if ($null -eq $display) { return $displays }
        $displays += $display
    }
    return $displays
}

function GetEnabledDisplays() {
    $enabledDisplays = @()
    foreach ($display in GetAllPotentialDisplays) {
        if ($display.Enabled) { $enabledDisplays += $display }
    }
    if ($enabledDisplays.Length -eq 0) { Write-PSFMessage -Level Warning -Message "No enabled displays found" }
    return $enabledDisplays
}

function GetPrimaryDisplay() {
    for ($i = 0; $i -lt $maxNbrDisplaysSupported; $i++) {
        $display = _GetDisplay($i)
        if ($display.Primary) { return $display }
    }
    Write-PSFMessage -Level Warning -Message "No primary display found"
    return $null
}

function GetDisplayByMonitorName($monitorName) {
    # Gets the first enabled display if any with the target friendly name of monitorName
    for ($i = 0; $i -lt $maxNbrDisplaysSupported; $i++) {
        $display = _GetDisplay($i)
        if ($display.Target.FriendlyName -eq $monitorName) { return $display }
    }
    Write-PSFMessage -Level Debug -Message "No display found for monitor $monitorName. Is the display enabled?"
    return $null
}

function _GetDisplay($index) {
    # We expect an error if the display source at that index does not exist- still try to fetch a couple times to be safe in case of any transient failures
    # TODO put these params in app config?
    $maxAttempts = 2
    $attemptDelayMs = 100
    for ($i = 0; $i -lt $maxAttempts; $i++) {
        Start-Sleep -Milliseconds $attemptDelayMs

        $displayDevice = New-Object DisplayDevices+DisplayDevice
        $displayDevice.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($displayDevice)
        $enumDisplayDevicesResult = [DisplayDevices]::EnumDisplayDevices([NullString]::Value, $index, [ref]$displayDevice, [DisplayDevices+EnumDisplayDevicesFlags]::None)
        if (-not $enumDisplayDevicesResult) { continue }

        $pathsCount = 0;
        $modesCount = 0;
        $displayConfigBufferSizesResult = [DisplayConfig]::GetDisplayConfigBufferSizes([DisplayConfig+QueryDisplayConfigFlags]::OnlyActivePaths, [ref]$pathsCount, [ref]$modesCount);
        if ([Win32Error]$displayConfigBufferSizesResult -ne [Win32Error]::ERROR_SUCCESS) {
            Write-PSFMessage -Level Critical -Message "Failed to get display configuration buffer for source index $index (error code $([Win32Error]$displayConfigBufferSizesResult))"
            continue
        }
        $paths = @()
        $modes = @()
        $displayConfigResult = [DisplayConfig]::QueryDisplayConfig([DisplayConfig+QueryDisplayConfigFlags]::OnlyActivePaths, [ref]$pathsCount, [ref]$paths, [ref]$modesCount, [ref]$modes);
        if ([Win32Error]$displayConfigResult -ne [Win32Error]::ERROR_SUCCESS) {
            Write-PSFMessage -Level Critical -Message "Failed to get display configuration for source index $index (error code $([Win32Error]$displayConfigResult))"
            continue
        }

        foreach ($path in $paths) {
            if ($path.sourceInfo.id -eq $index) {
                return [Display]::new($path.sourceInfo.id, $displayDevice, $path.targetInfo)
            }
        }
        return [Display]::new($index, $displayDevice)
    }
    Write-PSFMessage -Level Debug -Message "Consistently failed to get display index $index- this indicates there are less than $($index+1) display sources"
    return $null
}

function GetRefreshedDisplay($display) {
    # Get any potential display currently at the source id of the input display
    return _GetDisplay($display.Source.Id)
}

# TODO find out why the positions aren't getting applied properly (one is just getting placed next to the other, despite us supplying the correct offset values)
function SetPrimaryDisplay($display) {
    $enabledDisplays = GetEnabledDisplays
    $displayToUpdate = $null
    foreach ($enabledDisplay in $enabledDisplays) {
        if (-not $enabledDisplay.Equals($display)) { continue }
        if ($enabledDisplay.Primary) {
            Write-PSFMessage -Level Debug -Message "Display $($enabledDisplay.Description) is already the primary display, nothing to change"
            return $false
        }
        $displayToUpdate = $enabledDisplay
    }
    if (-not $displayToUpdate) {
        Write-PSFMessage -Level Debug -Message "Unable to set Display $($display.Description) as primary- could not find currently enabled display at its source and target"
        return $false
    }

    $displayToUpdateDeviceMode = $displayToUpdate.Source._GetDisplaySettingsDeviceMode()
    if ($null -eq $displayToUpdateDeviceMode) { return $false }
    $positionOffset = [Position]::new($displayToUpdateDeviceMode.dmPositionX, $displayToUpdateDeviceMode.dmPositionY)

    $displayToUpdateDeviceMode.dmPositionX = 0
    $displayToUpdateDeviceMode.dmPositionY = 0
    $primaryChangeDisplaySettingsFlags = [DisplaySettings+ChangeDisplaySettingsFlags]::UpdateRegistry -bor [DisplaySettings+ChangeDisplaySettingsFlags]::SetPrimary -bor [DisplaySettings+ChangeDisplaySettingsFlags]::NoReset
    $primaryChangeDisplaySettingsResult = [DisplaySettings]::ChangeDisplaySettingsEx($displayToUpdate.Source.Name, [ref]$displayToUpdateDeviceMode, $primaryChangeDisplaySettingsFlags)
    if ($primaryChangeDisplaySettingsResult -ne [DisplaySettings+ChangeDisplaySettingsResult]::DISP_CHANGE_SUCCESSFUL) {
        Write-PSFMessage -Level Critical -Message "Failed to adjust position of display $($displayToUpdate.Description) (error code $([DisplaySettings+ChangeDisplaySettingsResult]$primaryChangeDisplaySettingsResult))"
        return $false
    }

    foreach ($enabledDisplay in $enabledDisplays) {
        if ($enabledDisplay.Equals($displayToUpdate)) { continue }
        if (-not $enabledDisplay.Source._GetIsActive()) { continue }
        $otherDisplayDeviceMode = $enabledDisplay.Source._GetDisplaySettingsDeviceMode()
        if ($null -eq $otherDisplayDeviceMode) { return $false }
        $otherDisplayDeviceMode.dmPositionX -= $positionOffset.X
        $otherDisplayDeviceMode.dmPositionY -= $positionOffset.Y
        Write-PSFMessage -Level Debug -Message "Display $($enabledDisplay.Description) will be moved to position $($otherDisplayDeviceMode.dmPositionX),$($otherDisplayDeviceMode.dmPositionY)"
        $otherChangeDisplaySettingsFlags = [DisplaySettings+ChangeDisplaySettingsFlags]::UpdateRegistry -bor [DisplaySettings+ChangeDisplaySettingsFlags]::NoReset
        $otherChangeDisplaySettingsResult = [DisplaySettings]::ChangeDisplaySettingsEx($enabledDisplay.Source.Name, [ref]$otherDisplayDeviceMode, $otherChangeDisplaySettingsFlags)
        if ($otherChangeDisplaySettingsResult -ne [DisplaySettings+ChangeDisplaySettingsResult]::DISP_CHANGE_SUCCESSFUL) {
            Write-PSFMessage -Level Critical -Message "Failed to adjust position of display $($enabledDisplay.Description) (error code $([DisplaySettings+ChangeDisplaySettingsResult]$otherChangeDisplaySettingsResult))"
            return $false
        }
    }

    $commitChangeDisplaySettingsResult = [DisplaySettings]::ChangeDisplaySettingsEx([NullString]::Value)
    if ($commitChangeDisplaySettingsResult -ne [DisplaySettings+ChangeDisplaySettingsResult]::DISP_CHANGE_SUCCESSFUL) {
        Write-PSFMessage -Level Critical -Message "Unable to set Display $($display.Description) as primary- failed to commit display settings (error code $([DisplaySettings+ChangeDisplaySettingsResult]$commitChangeDisplaySettingsResult))"
        return $false
    }
    Write-PSFMessage -Level Verbose -Message "Display $($displayToUpdate.Description) set successfully as primary display"
    return $true
}

function SaveDisplaysToFile($displays, $filePath) {
    try {
        ($displays | ConvertTo-Json | Out-String).Trim() | Set-Content -Path $filePath
        return $true
    }
    catch {
        Write-PSFMessage -Level Critical -Message "Error saving displays to file $filePath" -ErrorRecord $_
        return $false
    }
}

function LoadDisplayStatesFromFile($filePath) {
    return (Get-Content -Raw -Path $filePath | ConvertFrom-Json)
}

function UpdateDisplaysFromFile($filePath) {
    $displayStates = LoadDisplayStatesFromFile -filePath $filePath
    if (-not $displayStates) { return $false }
    $allDisplays = GetAllPotentialDisplays
    if (-not $allDisplays) { return $false }
    Write-PSFMessage -Level Debug -Message "Enabled display states before monitor update from file:"
    foreach ($display in $allDisplays) { if ($display.Enabled) { Write-PSFMessage -Level Debug -Message $($display.ToTableString()) } }

    # First, enable any monitors and set primary as needed
    foreach ($displayState in @($displayStates)) {
        if ($displayState.Enabled -or $displayState.Primary) {
            $displayToUpdate = $null
            # Update the existing enabled display connected to the target if there is one, else the next available display source
            foreach ($display in $allDisplays) {
                if (($null -ne $displayState.Target.Id) -and ($display.Target.Id -eq $displayState.Target.Id)) {
                    $displayToUpdate = $display
                    break
                } elseif ((-not $displayToUpdate) -and ($display.Enabled -eq $false)) { 
                    $displayToUpdate = $display
                }
            }
            if (-not $displayToUpdate) {
                Write-PSFMessage -Level Warning -Message "No available display source found to enable for monitor $($displayState.Description) from file- are there open outputs on your host device?"
                continue
            }

            [void]($displayToUpdate.Enable($displayState.Target.Id))
            # Refresh target info after potential enable
            $displayToUpdate = DisplayManager_GetRefreshedDisplay -display $displayToUpdate
            if ($displayState.Primary) {
                [void](DisplayManager_SetPrimaryDisplay -display $displayToUpdate)
            }
        }
    }

    # Enabling and setting primary for displays may effect source -> target mapping. Refresh the active displays so that everything is accurate
    $currentEnabledDisplays = GetEnabledDisplays

    # Then, set graphics settings or disable as needed
    foreach ($displayState in @($displayStates)) {
        $displayToUpdate = $null
        foreach ($enabledDisplay in $currentEnabledDisplays) {
            if (($null -ne $displayState.Target.Id) -and ($enabledDisplay.Target.Id -eq $displayState.Target.Id)) { 
                $displayToUpdate = $enabledDisplay
                break
            }
        }
        if (-not $displayToUpdate) {
            Write-PSFMessage -Level Debug -Message "No enabled display found to update for display state of $($displayState.Description) from file"
            continue
        }
        if ($displayState.Enabled -eq $false) { 
            [void]($displayToUpdate.Disable())
            continue
        }
        if ($displayState.HdrInfo.HdrEnabled -eq $true) { [void]($displayToUpdate.EnableHdr()) }
        else { [void]($displayToUpdate.DisableHdr()) }
        $displayStateResolution = $displayState.Resolution
        # If we fail to set resolution with refresh rate, at least still try width x height
        $displayToUpdate.SetResolution($displayStateResolution.Width, $displayStateResolution.Height, $displayStateResolution.RefreshRate) `
            -or $displayToUpdate.SetResolution($displayStateResolution.Width, $displayStateResolution.Height)
    }

    # Also try to disable any currently enabled displays which aren't present in the file
    foreach ($display in $currentEnabledDisplays) {
        if ((@($displayStates) | Where-Object { $_.Target.Id -eq $display.Target.Id}).Length -eq 0) {
            [void]($display.Disable())
        }
    }

    Write-PSFMessage -Level Debug -Message "Enabled display states after monitor update from file:"
    # We may have disabled some displays in the last step- filter those out
    foreach ($display in $currentEnabledDisplays) { if ($display.Enabled) { Write-PSFMessage -Level Debug -Message $($display.ToTableString()) } }
}

function CurrentDisplayStatesAreSameAsFile($filePath) {
    $displayStates = LoadDisplayStatesFromFile -filePath $filePath
    if (-not $displayStates) { return $false }
    $allDisplays = GetAllPotentialDisplays
    if (-not $allDisplays) { return $false }
    foreach ($display in $allDisplays) {
        $matchingDisplayState = $null
        foreach ($displayState in $displayStates) {
            if (($null -ne $displayState.Target.Id) -and ($display.Target.Id -eq $displayState.Target.Id)) {
                $matchingDisplayState = $displayState
                break
            } elseif (($null -eq $displayState.Target.Id) -and ($display.Source.Id -eq $displayState.Source.Id)) { 
                $matchingDisplayState = $displayState
                break
            }
        }
        # Fail if any currently enabled displays aren't in the file or any current display states don't match enablement of any matching record in the file
        if (($display.Enabled -and -not $matchingDisplayState) -or ($display.Enabled -ne [boolean]$matchingDisplayState.Enabled)) { 
            return $false
        }
        if (-not $matchingDisplayState) { continue }
        # Fail if resolution or hdr differ on any current display which is in the file
        if ($display.HdrInfo.HdrEnabled -ne $matchingDisplayState.HdrInfo.HdrEnabled) { return $false }
        $displayResolution = $display.Resolution
        $refreshRateTolerance = 3 # Tolerance for when to consider a refresh rate close enough to be considered equivalent
        if ($displayResolution.Width -ne $matchingDisplayState.Resolution.Width `
                -or $displayResolution.Height -ne $matchingDisplayState.Resolution.Height `
                -or ($displayResolution.RefreshRate -and [Math]::Abs($displayResolution.RefreshRate - $matchingDisplayState.Resolution.RefreshRate) -gt $refreshRateTolerance)) {
            return $false
        }
    }
    return $true
}
