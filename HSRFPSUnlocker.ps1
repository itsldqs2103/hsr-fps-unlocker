# Compatible with PowerShell 5.1 and 7+
$ErrorActionPreference = 'Stop'

# Compatible script directory determination
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# Define target paths
$unlockerFolder = Join-Path -Path $scriptDir -ChildPath "FPS_Unlocker"
$jsonPath = Join-Path -Path $unlockerFolder -ChildPath "setting.json"

$registryPath = "HKCU:\Software\Cognosphere\Star Rail"
$valueName = "GraphicsSettings_Model_h2986158309"

# 1. Update Registry FPS value
if (Test-Path -Path $registryPath) {
    try {
        $rawBytes = Get-ItemPropertyValue -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue

        if ($null -ne $rawBytes) {
            $jsonString = [System.Text.Encoding]::UTF8.GetString($rawBytes).TrimEnd("`0")
            $config = $jsonString | ConvertFrom-Json

            if ($config.FPS -notin 30, 60, 120) {
                Write-Host "Current FPS ($($config.FPS)) is not 30, 60, or 120. Updating to 120..." -ForegroundColor Yellow
                $config.FPS = 120

                # Re-serialize JSON with trailing null byte required by Unity registry entries
                $updatedJson = ($config | ConvertTo-Json -Compress) + "`0"
                $updatedBytes = [System.Text.Encoding]::UTF8.GetBytes($updatedJson)

                Set-ItemProperty -Path $registryPath -Name $valueName -Value $updatedBytes -Type Binary
                Write-Host "Successfully updated registry FPS to 120." -ForegroundColor Green
            }
            else {
                Write-Host "FPS is currently set to $($config.FPS). No registry change needed." -ForegroundColor Cyan
            }
        }
        else {
            Write-Warning "Registry value '$valueName' was not found."
        }
    }
    catch {
        Write-Warning "Failed to read/modify registry: $_"
    }
}
else {
    Write-Warning "Registry key '$registryPath' does not exist."
}

# 2. Process Configuration & File Selection
$exePath = $null

if (Test-Path -Path $jsonPath) {
    Write-Host "Found existing configuration: $jsonPath" -ForegroundColor Green
    $savedSettings = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
    $exePath = $savedSettings.GameExePath
}
else {
    Write-Host "No setting.json found. Opening file picker..." -ForegroundColor Yellow

    # Modern OpenFileDialog using WPF / Microsoft.Win32 (Native OS look)
    Add-Type -AssemblyName PresentationFramework
    $fileDialog = New-Object Microsoft.Win32.OpenFileDialog
    $fileDialog.Filter = "StarRail.exe|StarRail.exe|Executable Files (*.exe)|*.exe"
    $fileDialog.Title = "Select StarRail.exe Location"
    $fileDialog.CheckFileExists = $true

    if ($fileDialog.ShowDialog() -eq $true) {
        $exePath = $fileDialog.FileName
        $gameDir = [System.IO.Path]::GetDirectoryName($exePath)

        # Ensure FPS_Unlocker folder exists
        $null = New-Item -Path $unlockerFolder -ItemType Directory -Force

        # Create settings object
        $settingsData = [PSCustomObject]@{
            GameExePath  = $exePath
            GameDir      = $gameDir
            FPS          = 120
            LastModified = (Get-Date).ToString("o") # ISO 8601 format
        }

        # Save JSON with modern UTF-8 encoding
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $settingsData | ConvertTo-Json -Depth 3 | Set-Content -Path $jsonPath -Encoding utf8NoBOM
        }
        else {
            $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($jsonPath, ($settingsData | ConvertTo-Json -Depth 3), $utf8NoBomEncoding)
        }
        
        Write-Host "Saved configuration to: $jsonPath" -ForegroundColor Green
    }
    else {
        Write-Warning "No file selected. Operation canceled."
    }
}

# 3. Launch Executable
if ($exePath -and (Test-Path -Path $exePath)) {
    Write-Host "Launching game from: $exePath" -ForegroundColor Green
    Start-Process -FilePath $exePath -WorkingDirectory ([System.IO.Path]::GetDirectoryName($exePath))
}
else {
    Write-Error "Executable path not found or invalid: '$exePath'"
}