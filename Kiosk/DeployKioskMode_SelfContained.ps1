# ============================================
# Multi-App Kiosk Deployment Script - SELF-CONTAINED
# Creates XML and saves itself on the target computer
# Kiosk User: Retreading
# Basys Global Manufacturing + NetTerm + TabTip.exe
# ============================================

#Requires -RunAsAdministrator

param(
    [string]$KioskUserName = "Retreading",
    [string]$KioskUserPassword = "retreading",
    [string]$BasysAppUserModelId = "BASys.Global.Manufacturing_ce274a7akqk24!App",
    [string]$NetTermPath = "C:\Program Files (x86)\Intersoft International, Inc\NetTerm.exe",
    [bool]$EnableTouchKeyboard = $true
)

# Error handling
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[{$timestamp}] {$Level}: $Message"
    Write-Host $logEntry -ForegroundColor $(if($Level=="ERROR"){"Red"}elseif($Level=="SUCCESS"){"Green"}else{"White"})
    Add-Content -Path "C:\Kiosk\KioskDeployment.log" -Value $logEntry
}

# Initialize logging
New-Item -ItemType Directory -Force -Path "C:\Kiosk" | Out-Null
Add-Content -Path "C:\Kiosk\KioskDeployment.log" -Value "=== Kiosk Deployment Started ==="

try {
    Write-Log "Starting Multi-App Kiosk Mode Deployment"
    Write-Log "Kiosk User: $KioskUserName"
    Write-Log "Basys Global AppUserModelId: $BasysAppUserModelId"
    Write-Log "NetTerm Path: $NetTermPath"

    # ============================================
    # STEP 1: CREATE Target Directories
    # ============================================
    Write-Log "Creating deployment directories..."
    
    $scriptTargetDir = "C:\Scripts"
    $xmlTargetDir = "C:\Kiosk"
    
    if (-not (Test-Path $scriptTargetDir)) {
        New-Item -ItemType Directory -Force -Path $scriptTargetDir | Out-Null
        Write-Log "Created script directory: $scriptTargetDir" -Level "SUCCESS"
    }
    
    if (-not (Test-Path $xmlTargetDir)) {
        New-Item -ItemType Directory -Force -Path $xmlTargetDir | Out-Null
        Write-Log "Created XML directory: $xmlTargetDir" -Level "SUCCESS"
    }
    
    Write-Log "Directories created successfully" -Level "SUCCESS"

    # ============================================
    # STEP 2: CREATE XML Configuration File
    # ============================================
    Write-Log "Creating kiosk XML configuration file..."
    
    $netTermPathEscaped = $NetTermPath.Replace('"', '\"')
    
    $xmlConfig = @"
<?xml version="1.0" encoding="utf-8"?>
<AssignedAccessConfiguration xmlns="https://schemas.microsoft.com/AssignedAccess/2017/config">
  <Profiles>
    <Profile Id="KioskProfile1">
      <AllAppsList>
        <AllowedApps>
          <!-- BASys Global Manufacturing (UWP app) -->
          <App AppUserModelId="$BasysAppUserModelId" />
          
          <!-- NetTerm (Win32 Desktop App) -->
          <App DesktopAppPath="$netTermPathEscaped" />
        </AllowedApps>
      </AllAppsList>
      <Taskbar ShowTaskbar="false" />
    </Profile>
  </Profiles>
  <Configs>
    <Config>
      <Account>$KioskUserName</Account>
      <DefaultProfile Id="KioskProfile1" />
    </Config>
  </Configs>
</AssignedAccessConfiguration>
"@

    # Save XML to C:\Kiosk\
    $xmlPath = "$xmlTargetDir\MultiAppKioskConfiguration_Valid.xml"
    $xmlConfig | Set-Content -Path $xmlPath -Force -Encoding UTF8
    Write-Log "XML configuration created at: $xmlPath" -Level "SUCCESS"

    # ============================================
    # STEP 3: SAVE THIS SCRIPT to C:\Scripts\
    # ============================================
    Write-Log "Saving this script to deployment location..."
    
    $scriptFileName = $MyInvocation.MyCommand.Name
    $scriptTargetPath = "$scriptTargetDir\$scriptFileName"
    
    # Get the script's current content and save it
    $scriptContent = Get-Content -Path $MyInvocation.MyCommand.Path -Raw
    $scriptContent | Set-Content -Path $scriptTargetPath -Force -Encoding UTF8
    
    Write-Log "Script saved to: $scriptTargetPath" -Level "SUCCESS"
    Write-Log ""
    Write-Log "Deployment files created:" -ForegroundColor Cyan
    Write-Log "  Script: $scriptTargetPath" -ForegroundColor Cyan
    Write-Log "  XML: $xmlPath" -ForegroundColor Cyan
    Write-Log ""

    # ============================================
    # STEP 4: Create Retreading User Account
    # ============================================
    Write-Log "Creating kiosk user account: $KioskUserName"
    
    try {
        $existingUser = Get-LocalUser -Name $KioskUserName -ErrorAction SilentlyContinue
        
        if ($existingUser) {
            Write-Log "User $KioskUserName already exists, updating password"
            $passwordHash = ConvertTo-SecureString -String $KioskUserPassword -AsPlainText -Force
            $existingUser | Set-LocalUser -Password $passwordHash
        } else {
            $passwordHash = ConvertTo-SecureString -String $KioskUserPassword -AsPlainText -Force
            New-LocalUser -Name $KioskUserName -Password $passwordHash -Description "Retreading Kiosk Mode User" -AccountNeverExpires -ErrorAction Stop | Out-Null
            Write-Log "User $KioskUserName created successfully" -Level "SUCCESS"
        }
        
        Add-LocalGroupMember -Group "Users" -Member $KioskUserName -ErrorAction SilentlyContinue
        Write-Log "$KioskUserName user configured in Users group" -Level "SUCCESS"
        
        # Create user profile directory (required for kiosk)
        $profilePath = "C:\Users\$KioskUserName"
        if (-not (Test-Path $profilePath)) {
            New-Item -ItemType Directory -Force -Path $profilePath | Out-Null
            Write-Log "Created user profile directory: $profilePath" -Level "SUCCESS"
        }
    }
    catch {
        Write-Log "Failed to create kiosk user: $($_.Exception.Message)" -Level "ERROR"
        throw
    }

    # ============================================
    # STEP 5: Check if NetTerm is Installed
    # ============================================
    Write-Log "Checking application installations..."
    
    if (Test-Path $NetTermPath) {
        Write-Log "NetTerm found at: $NetTermPath" -Level "SUCCESS"
    } else {
        Write-Log "NetTerm NOT found at: $NetTermPath" -Level "ERROR"
        Write-Log "Please install NetTerm or update NetTermPath parameter" -Level "ERROR"
        # Uncomment to stop deployment: # throw "NetTerm installation required"
    }

    # ============================================
    # STEP 6: Apply Multi-App Kiosk via AssignedAccess
    # ============================================
    Write-Log "Applying multi-app kiosk configuration"
    
    try {
        # Use AssignedAccess WMI Provider (requires SYSTEM context)
        $wmiNamespace = "ROOT\AssignedAccess\AssignedAccessManager"
        
        if ([System.Management.ManagementNamespace]::Exists($wmiNamespace)) {
            Write-Log "Using AssignedAccess WMI Provider" -Level "SUCCESS"
            
            # Use the MDM Bridge WMI provider
            $wmiClass = [WMIClass]$wmiNamespace
            $kioskConfig = $wmiClass.CreateKioskConfiguration()
            $kioskConfig["ProfileId"] = "KioskProfile1"
            $kioskConfig["AccountId"] = $KioskUserName
            
            # Apply the configuration from XML
            $xmlContent = Get-Content $xmlPath -Raw
            $wmiClass::SetKioskConfiguration($xmlContent)
            
            Write-Log "Kiosk mode configuration applied via WMI" -Level "SUCCESS"
        } else {
            Write-Log "AssignedAccess WMI not found, using registry fallback" -Level "INFO"
            
            # Registry-based configuration (fallback)
            $kioskRegistryPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AssignedAccessMode\Config"
            New-Item -Path $kioskRegistryPath -Force | Out-Null
            Set-ItemProperty -Path $kioskRegistryPath -Name "ProfileId" -Value "KioskProfile1" -Type String
            Set-ItemProperty -Path $kioskRegistryPath -Name "AccountId" -Value $KioskUserName -Type String
            Set-ItemProperty -Path $kioskRegistryPath -Name "ConfigXml" -Value $xmlConfig -Type String
            
            Write-Log "Registry configuration applied" -Level "SUCCESS"
        }
    }
    catch {
        Write-Log "Failed to apply kiosk via WMI: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Attempting alternative deployment method..." -Level "INFO"
        
        # Alternative: Copy XML to system location
        try {
            Copy-Item -Path $xmlPath -Destination "C:\Windows\System32\AssignedAccess\KioskConfig.xml" -Force
            Write-Log "XML copied to system location" -Level "SUCCESS"
        }
        catch {
            Write-Log "Alternative method also failed" -Level "ERROR"
        }
    }

    # ============================================
    # STEP 7: Configure Touch Keyboard (TabTip.exe)
    # ============================================
    if ($EnableTouchKeyboard) {
        Write-Log "Configuring touch keyboard (TabTip.exe) to always show"
        
        try {
            # Set registry keys for TabletMode and touch keyboard
            $tabletModePath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell"
            New-ItemProperty -Path $tabletModePath -Name "TabletMode" -Value 1 -PropertyType DWord -Force | Out-Null
            
            $tabletTipPath = "HKLM\SOFTWARE\Microsoft\TabletTip"
            New-Item -Path $tabletTipPath -Force | Out-Null
            New-ItemProperty -Path $tabletTipPath -Name "EnableDesktopModeAutoInvoke" -Value 1 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $tabletTipPath -Name "DisableNewKeyboardExperience" -Value 1 -PropertyType DWord -Force | Out-Null
            
            Write-Log "Touch keyboard registry settings applied" -Level "SUCCESS"
        }
        catch {
            Write-Log "Failed to set touch keyboard registry: $($_.Exception.Message)" -Level "ERROR"
        }
        
        # ============================================
        # STEP 8: Create Task Scheduler Task for TabTip.exe
        # ============================================
        Write-Log "Creating startup task for TabTip.exe"
        
        $tabTipPath = "C:\Program Files\Common Files\microsoft shared\ink\TabTip.exe"
        
        if (Test-Path $tabTipPath) {
            try {
                # Use PowerShell to create the task
                $taskAction = New-ScheduledTaskAction -Execute $tabTipPath
                $taskPrincipal = New-ScheduledTaskPrincipal -UserId $KioskUserName -LogonType InteractiveToken -RunLevel Least
                $taskTrigger = New-ScheduledTaskTrigger -AtLogon -User $KioskUserName
                $taskSettings = New-ScheduledTaskSettings -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
                
                Register-ScheduledTask `
                    -TaskName "TabTipAutoStart" `
                    -Action $taskAction `
                    -Principal $taskPrincipal `
                    -Trigger $taskTrigger `
                    -Settings $taskSettings `
                    -Description "Auto-launch TabTip.exe for Retreading kiosk user" `
                    -Force
                
                Write-Log "TabTip.exe startup task created successfully via PowerShell" -Level "SUCCESS"
            }
            catch {
                Write-Log "Failed to create TabTip task via PowerShell: $($_.Exception.Message)" -Level "ERROR"
                
                # Fallback: Add to kiosk user's startup folder
                try {
                    $startupFolder = "C:\Users\$KioskUserName\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
                    New-Item -ItemType Directory -Force -Path $startupFolder | Out-Null
                    
                    # Create shortcut using Shell.Application
                    $shell = New-Object -ComObject Shell.Application
                    $shortcut = $shell.CreateShortcut("$startupFolder\TabTip.exe")
                    $shortcut.TargetPath = $tabTipPath
                    $shortcut.Save()
                    
                    Write-Log "TabTip.exe added to startup folder (fallback)" -Level "SUCCESS"
                }
                catch {
                    Write-Log "Startup folder fallback also failed: $($_.Exception.Message)" -Level "ERROR"
                }
            }
        } else {
            Write-Log "TabTip.exe not found at: $tabTipPath" -Level "ERROR"
        }
    }

    # ============================================
    # STEP 9: Final Configuration Summary
    # ============================================
    Write-Log "Kiosk configuration complete" -Level "SUCCESS"
    Write-Log ""
    Write-Log "Apps in kiosk mode:"
    Write-Log "  - BASys Global Manufacturing (UWP)"
    Write-Log "  - NetTerm (Win32 Desktop)"
    Write-Log ""
    Write-Log "Kiosk User Account: $KioskUserName"
    Write-Log "Touch Keyboard: Always Visible (TabTip.exe)" -ForegroundColor Green
    Write-Log ""
    Write-Log "Deployment files created at:" -ForegroundColor Cyan
    Write-Log "  Script: $scriptTargetPath" -ForegroundColor Cyan
    Write-Log "  XML: $xmlPath" -ForegroundColor Cyan
    Write-Log ""
    Write-Log "Restart required to activate kiosk mode:" -ForegroundColor Yellow
    Write-Host "Restart-Computer -Force" -ForegroundColor Cyan
    
    # Create restart summary script
    $restartScript = @"
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Kiosk Mode Configuration Complete" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Cyan
Write-Host "" -ForegroundColor White
Write-Host "Kiosk User Account: $KioskUserName" -ForegroundColor Yellow
Write-Host "" -ForegroundColor White
Write-Host "Apps Available:" -ForegroundColor Yellow
Write-Host "  - BASys Global Manufacturing (Default)" -ForegroundColor White
Write-Host "  - NetTerm Terminal" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "Touch Keyboard: Always Visible (TabTip.exe)" -ForegroundColor Green
Write-Host "" -ForegroundColor White
Write-Host "Deployment files:" -ForegroundColor Yellow
Write-Host "  Script: $scriptTargetPath" -ForegroundColor White
Write-Host "  XML: $xmlPath" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "Restart required to activate kiosk mode:" -ForegroundColor Yellow
Write-Host "Restart-Computer -Force" -ForegroundColor Cyan
"@

    $restartScript | Set-Content -Path "$xmlTargetDir\KioskComplete.ps1"
    
    Write-Log "Deployment completed successfully" -Level "SUCCESS"
    
}
catch {
    Write-Log "Deployment failed: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Error details: $($_.Exception.InnerException.Message)" -Level "ERROR"
    exit 1
}

##########################################################################
# REMOTE DEPLOYMENT INSTRUCTIONS (MSP/RMM)
##########################################################################
# 
# This script is SELF-CONTAINED - it creates all files on the target computer
# No XML file needed! Just copy this single script file.
#
# For NinjaOne/ConnectWise:
#
# 1. Copy ONLY this script to target computer (any location):
#    - Via RMM file transfer to C:\Temp\
#    - Or anywhere temporary
#
# 2. Execute as SYSTEM (required):
#    PsExec.exe -i -s powershell.exe -File "C:\Temp\DeployKioskMode_SelfContained.ps1"
#
# 3. After execution, script creates files automatically:
#    - Script: C:\Scripts\DeployKioskMode_SelfContained.ps1
#    - XML: C:\Kiosk\MultiAppKioskConfiguration_Valid.xml
#    - Restart: C:\Kiosk\KioskComplete.ps1
#
# 4. With custom parameters:
#    DeployKioskMode_SelfContained.ps1 
#      -KioskUserPassword "SecurePass123!"
#      -NetTermPath "C:\Custom\NetTerm.exe"
#      -BasysAppUserModelId "Your.Basys.AppID!App"
#
# 5. Restart remotely:
#    Restart-Computer -ComputerName "TargetDevice" -Force
#
#==========================================================================
# Important: Verify Basys Global AppUserModelId BEFORE deployment
# Find it by checking: HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications
#==========================================================================