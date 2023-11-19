Sunshine Automation Suite
TODO: Add user facing documentation (modules can have their own developer facing interactive help via powershell module discovery tools)

Sample settings.json:
{
    // Delay (in seconds) after script completes to allow sunshine to start the stream
    // Higher values ensure that automations are complete by the time the stream starts (eg giving a monitor time to wake up)
    // Lower values mean for shorter loading screens when starting a streaming session
    "stream_start_delay": 3,
    // Delay (in seconds) after sunshine is no longer streaming for the script to cancel itself and revert any streaming automations
    // Context: Quitting a session in moonlight also reverts any streaming automations- this mechanism handles sessions which end unexpectedly (eg internet outage)
    "stream_end_grace_period": 60,
    // The script will keep a temp snapshot of current monitor configuration during a stream to know what to revert back to when the stream ends- this is the directory to keep that snapshot
    "temp_config_save_location": "%TEMP%\\SunshineDisplayAutomation",
    // Options for automating global HDR enablement while streaming a game via Sunshine:
    // SYNC_HDR_ENABLEMENT_TO_CLIENT- set HDR enablement based on Moonlight settings
    // NO_CHANGE- do not change HDR settings
    "hdr_while_streaming": "SYNC_HDR_TO_CLIENT",
    "monitors": [
        {
            // ID of monitor in your graphics system. Prepopulated on install.
            // Can be refreshed with "reset_and_refresh_monitor_config.ext"- however all existing monitor settings will be lost
            // Can also be found manually with Sunshine's tools\dgxi-info.exe
            "monitor_id": "MONITOR\\FL_2701\\{4d36e96e-e325-11ce-bfc1-08002be10318}\\0000",
            // Options for automating a particular monitor's resolution while streaming a game via Sunshine:
            // DISABLE_MONITOR- disable monitor (power of monitor will remain unchanged, but video will no longer be output to it)
            // SYNC_RESOLUTION_TO_CLIENT- set monitor resolution (including refresh rate) based on Moonlight settings
            // CUSTOM- change resolution settings to custom values based on custom_resolution_while_streaming parameter
            // NO_CHANGE- do not change resolution settings
            "resolution_while_streaming": "DISABLE_MONITOR"
        },
        {
            "monitor_id": "MONITOR\\FL_2701\\{4d36e96e-e325-11ce-bfc1-08002be10318}\\0001",
            "resolution_while_streaming": "SYNC_RESOLUTION_TO_CLIENT"
        },
        {
            "monitor_id": "MONITOR\\FL_2701\\{4d36e96e-e325-11ce-bfc1-08002be10318}\\0002",
            "resolution_while_streaming": "CUSTOM",
            // Required when resolution_while_streaming is set to CUSTOM, specific resolution to set while streaming
            "custom_resolution_while_streaming": {
                // Number of pixels wide
                "width": 1920,
                // Number of pixels tall
                "height": 1080,
                // Refresh rate in frames per second
                "refresh_rate": 60
            }
        },
        {
            "monitor_id": "MONITOR\\FL_2701\\{4d36e96e-e325-11ce-bfc1-08002be10318}\\0003",
            "resolution_while_streaming": "NO_CHANGE"
        }
    ]
}

Sample app/config.json
{
    // Log level for the application logs, options: None|Error|Warning|Info|Debug|Verbose
    "log_level": "Error"
    // Delay (in seconds) after script completes to allow sunshine to start the stream
    // Higher values ensure that automations are complete by the time the stream starts (eg giving a monitor time to wake up)
    // Lower values mean for shorter loading screens when starting a streaming session
    "stream_start_delay": 3,
    // Delay (in seconds) after sunshine is no longer streaming for the script to cancel itself and revert any streaming automations
    // Context: Quitting a session in moonlight also reverts any streaming automations- this mechanism handles sessions which end unexpectedly (eg internet outage)
    "stream_end_grace_period": 60,
    // The script will keep a temp snapshot of current monitor configuration during a stream to know what to revert back to when the stream ends- this is the directory to keep that snapshot
    "temp_config_save_location": "%TEMP%\\SunshineDisplayAutomation",
}