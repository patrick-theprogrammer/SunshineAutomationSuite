# Simple script to import the public portion of all libraries in this directory
Set-Location $PSScriptRoot
Add-Type -Path .\DisplayInterop\DisplayConfig.cs -IgnoreWarnings
Add-Type -Path .\DisplayInterop\DisplayDevices.cs -IgnoreWarnings
Add-Type -Path .\DisplayInterop\DisplaySettings.cs -IgnoreWarnings
Add-Type -Path .\DisplayInterop\Win32Errors.cs -IgnoreWarnings
