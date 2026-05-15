# Logging function
function Write-Log {
    param(
        [string]$Step,
        [string]$Status = "SUCCESS",
        [string]$Message = ""
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Step : $Status - $Message"
    Write-Output $logEntry
    $logEntry | Out-File "C:\temp\BG_Update.log" -Append -Encoding UTF8
}

$ErrorActionPreference = "Continue"   

$tempDir = "c:\TEMP\Dependencies"
$null = New-Item -ItemType Directory -Path $tempDir -Force


# Combined Dependencies + Bundle Provisioning
Write-Log "App Provisioning" "START"

$dependencies = @(
    @{ Name = "Microsoft.NET.CoreRuntime.2.2"; File = "Microsoft.NET.CoreRuntime.2.2.appx"; Url = "https://github.com/PCSSupport/BASysGlobal/raw/refs/heads/main/Dependencies/x64/Microsoft.NET.CoreRuntime.2.2.appx" },
    @{ Name = "Microsoft.NET.CoreFramework.Debug.2.2"; File = "Microsoft.NET.CoreFramework.Debug.2.2.appx"; Url = "https://github.com/PCSSupport/BASysGlobal/raw/refs/heads/main/Dependencies/x64/Microsoft.NET.CoreFramework.Debug.2.2.appx" },
    @{ Name = "Microsoft.VCLibs.140.00_14.0.27825.0_x64__8wekyb3d8bbwe"; File = "Microsoft.VCLibs.x64.14.00.appx"; Url = "https://github.com/PCSSupport/BASysGlobal/raw/refs/heads/main/Dependencies/x64/Microsoft.VCLibs.x64.14.00.appx" }
)

$bundleUrl = "https://github.com/PCSSupport/BASysGlobal/raw/refs/heads/main/Retread.Mfg.Client.Windows_1.57.0.128_x64.msixbundle"
$bundleName = "Retread.Mfg.Client.Windows_1.57.0.128_x64.msixbundle"
$bundlePath = "$tempDir\$bundleName"

$depPaths = @()

Write-Log "Dependency Download" "START" "Downloading dependency packages..."

foreach ($dep in $dependencies) {
    $destPath = Join-Path $tempDir $dep.File
    try {
        Invoke-WebRequest -Uri $dep.Url -OutFile $destPath -UseBasicParsing -ErrorAction Stop
        Write-Log "Dependency Download" "SUCCESS" "Downloaded $($dep.Name) to $destPath"
        $depPaths += $destPath
    }
    catch {
        Write-Log "Dependency Download" "FAILED" "$($dep.Name): $($_.Exception.ToString())"
        throw
    }
}

Write-Log "Dependency Install" "INFO" "Provisioning individual dependencies..."
foreach ($depPath in $depPaths) {
    try {
        Add-AppxProvisionedPackage -Online -PackagePath $depPath -SkipLicense -ErrorAction Stop
        Write-Log "Dependency Install" "SUCCESS" "Provisioned $depPath"
    }
    catch {
        Write-Log "Dependency Install" "FAILED" $_.Exception.ToString()
        throw
    }
}
try {
    Invoke-WebRequest -Uri $bundleUrl -OutFile $bundlePath -UseBasicParsing -ErrorAction Stop
    Write-Log "Bundle Download" "SUCCESS" "Downloaded bundle to $bundlePath"
}
catch {
    Write-Log "Bundle Download" "FAILED" $_.Exception.ToString()
    throw
}
    try {
        $appDisplayName = "Retread.Mfg.Client.Windows"

        Write-Log "Retread Client Install" "INFO" "Provisioning bundle for future users..."
        DISM /Online /Add-ProvisionedAppxPackage /PackagePath $bundlePath /SkipLicense
        Write-Log "Retread Client Install" "SUCCESS" "Bundle provisioned for future users"
    }
    catch {
        Write-Log "App Provisioning" "FAILED" $_.Exception.ToString()
        throw
    }
}
catch {
    Write-Log "App Provisioning" "FAILED" $_.Exception.ToString()
}

# Cleanup temp files (keep log)
Write-Log "Temp Cleanup" "START"
$logPath = "C:\temp\BG_Update.log"
Get-ChildItem "C:\temp\" -Force | Where-Object { $_.FullName -ne $logPath } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Log "Temp Cleanup" "SUCCESS" "Cleaned C:\temp\ (log preserved)"

Write-Log "=== FINAL ERROR DUMP ===" "INFO"
$Error | ForEach-Object { Write-Log "GLOBAL ERROR" "ERROR" $_.Exception.Message }

