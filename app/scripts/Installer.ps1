param(
    [switch]$uninstall
)

# Get the current value of global_prep_cmd from the configuration file
function GetSunshineGlobalPrepCommands {
    # Read the contents of the configuration file into an array of strings
    $config = Get-Content -Path $sunshineConfigPath
    # Find the line that contains the global_prep_cmd setting
    $globalPrepCmdLine = $config | Where-Object { $_ -match '^global_prep_cmd\s*=' }
    # Extract the current value of global_prep_cmd
    if ($globalPrepCmdLine -match '=\s*(.+)$') {
        return $matches[1]
    }
    else {
        Write-PSFMessage -Level Debug -Message "Unable to extract current value of global_prep_cmd, this probably means user has not setup prep commands yet."
        return [object[]]@()
    }
}

# Set a new value for global_prep_cmd in the configuration file
function SetSunshineGlobalPrepCommands {
    # The new value for global_prep_cmd as an array of objects
    param ( [object[]]$Value )

    if ($null -eq $Value) { $Value = [object[]]@() }
    # Read the contents of the configuration file into an array of strings
    $sunshineConfig = Get-Content -Path $sunshineConfigPath
    # Get the current value of global_prep_cmd as a JSON string
    $currentValueJson = GetSunshineGlobalPrepCommands -ConfigPath $sunshineConfigPath
    # Convert the new value to a JSON string
    $newValueJson = ConvertTo-Json -InputObject $Value -Compress
    # Replace the current value with the new value in the config array
    try {
        $sunshineConfig = $sunshineConfig -replace [regex]::Escape($currentValueJson), $newValueJson
    }
    catch {
        # If it failed, it probably does not exist yet.
        # In the event the config only has one line, we will cast this to an object array so it appends a new line automatically.
        if ($Value.Length -eq 0) {
            [object[]]$sunshineConfig += "global_prep_cmd = []"
        }
        else {
            [object[]]$sunshineConfig += "global_prep_cmd = $($newValueJson)"
        }
    }
    # Write the modified config array back to the file
    $sunshineConfig | Set-Content -Path $sunshineConfigPath -Force
}

# Remove any existing commands that contain the main script from the current sunshine global_prep_cmd value.
function GetSunshineGlobalPrepCommandsWithoutScript() {
    # Get the current value of global_prep_cmd as a JSON string
    $globalPrepCmdJson = GetSunshineGlobalPrepCommands -ConfigPath $sunshineConfigPath
    # Convert the JSON string to an array of objects
    $globalPrepCmdArray = $globalPrepCmdJson | ConvertFrom-Json
    $filteredCommands = @()
    # Remove any SunshineAutomationSuite Commands
    for ($i = 0; $i -lt $globalPrepCmdArray.Count; $i++) {
        if (-not ($globalPrepCmdArray[$i].do -like "*SunshineAutomationSuite*")) {
            $filteredCommands += $globalPrepCmdArray[$i]
        }
    }
    return [object[]]$filteredCommands
}

# Add a new command to run the main script to the current sunshine global_prep_cmd value.
function GetSunshineGlobalPrepCommandsWithScript() {
    # Remove any existing commands that contain the main script from the global_prep_cmd value
    $globalPrepCmdArray = GetSunshineGlobalPrepCommandsWithoutScript -ConfigPath $sunshineConfigPath
    # Create a new object with the command to run the main script
    $sunshineAutomationSuiteCommand = [PSCustomObject]@{
        do       = "powershell.exe -Executionpolicy Bypass -WindowStyle Hidden -File `"$PSScriptRoot\StreamStart.ps1`""
        elevated = "false"
        undo     = "powershell.exe -Executionpolicy Bypass -WindowStyle Hidden -File `"$PSScriptRoot\StreamQuit.ps1`""
    }
    # Add the new object to the global_prep_cmd array
    [object[]]$globalPrepCmdArray += $sunshineAutomationSuiteCommand
    return [object[]]$globalPrepCmdArray
}

# Restart the sunshine service.
function RestartSunshineService() {
    $sunshineService = Get-Service -ErrorAction Ignore | Where-Object { $_.Name -eq 'sunshinesvc' -or $_.Name -eq 'SunshineService' }
    $sunshineService | Restart-Service  -WarningAction SilentlyContinue
}



Write-PSFMessage -Level Verbose -Message "$(if ($uninstall) {"un"})installing Sunshine Automation Suite..."

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

# Sunshine configuration file path.
$sunshineConfigPath = $appconfig.sunshine_config_path

# If the current user is not an administrator, re-launch this script with elevated privileges.
$isAdmin = [bool]([System.Security.Principal.WindowsIdentity]::GetCurrent().groups -match 'S-1-5-32-544')
if (-not $isAdmin) {
    Start-Process powershell.exe  -Verb RunAs -ArgumentList "-ExecutionPolicy RemoteSigned -NoLogo -NoExit -File `"$PSCommandPath`"$(if ($uninstall) { " -uninstall" })"
    exit
}

# Only run if sunshine is installed at the expected path.
if (-not $appconfig.sunshine_config_path -or -not $(Test-Path $sunshineConfigPath -PathType Leaf)) {
    Write-PSFMessage -Level Critical -Message "Sunshine Automation Suite $(if ($uninstall) {"un"})install failed. Unable to find sunshine configuration file at $sunshineConfigPath"
    exit
}

# If installing, install PSFramework dependency on machine if not already done
if (-not $uninstall -and -not (Get-Module PSFramework -ListAvailable)) {
    Install-Module PSFramework -Force
}

# Add or remove main script from sunshine global prep command configuration depending on uninstall argument switch.
$commands = @()
if (-not $uninstall) {
    $commands = GetSunshineGlobalPrepCommandsWithScript
}
else {
    $commands = GetSunshineGlobalPrepCommandsWithoutScript 
}
SetSunshineGlobalPrepCommands $commands

# Restart the sunshine service to apply config changes.
RestartSunshineService

Write-PSFMessage -Level Verbose -Message "Sunshine Automation Suite $(if ($uninstall) {"un"})installed successfully. You can close this window."
Write-Host "Sunshine Automation Suite $(if ($uninstall) {"un"})installed successfully. You can close this window."
