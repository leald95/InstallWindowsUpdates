function install_updates {
<#
- May 22, 2018 - V1.0 - DPO
+ Initial release.
- May 23, 2018 - V1.1 - DPO
+ Added check for packages/modules before force-installing them.
+ Added some output text.
+ Added 'ListOnly' switch, which will cause it to only display approved updates (not download or install them).
- May 23, 2018 - V1.2 - DPO
+ Added 'MicrosoftUpdate' switch to force the check to go to Microsoft Update (circumventing WSUS/WSUS approvals).
- v1.4 - DPO - July, 2021
+ Implemented NoAutoReboot switch.
+ Implemented RebootAtMidnight switch (via PSShutdown).
+ Added more descriptive output.
+ Implemented Module updating, including SkipModuleUpdate flag.
- v1.5 - DPO - Feb. 2022
+ Implemented "SkipDrivers" switch.
+ Implemented "SkipFirmware" switch.
#>
param (
	[switch]$ResetDistributionFolder,
	[switch]$ListOnly,
	[switch]$MicrosoftUpdate,
	[switch]$NoAutoReboot,
	[switch]$RebootAtMidnight,
	[switch]$SkipModuleUpdate,
	[switch]$SkipDrivers,
	[switch]$SkipFirmware
)

if ($ResetDistributionFolder) {
	Write-Host 'Stopping services...'
	Stop-Service 'Windows Update' -Force
	Stop-Service cryptSvc -Force
	Stop-Service DoSvc -Force
	Stop-Service bits -Force
	Stop-Service msiserver -Force

	Write-Host 'Removing SoftwareDistribution folder...'
	Remove-Item 'C:\Windows\SoftwareDistribution\' -Force -Recurse
	Write-Host 'Removing CatRoot2 folder...'
	Remove-Item 'C:\Windows\System32\catroot2\' -Force -Recurse

	Write-Host 'Starting services...'
	Start-Service cryptSvc
	Start-Service 'Windows Update'
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Get-PackageProvider -Name 'NuGet')) {
	Write-Host 'Installing NuGet...'
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}

if (-not (Get-InstalledModule -Name 'PSWindowsUpdate')) {
	Write-Host 'Installing Windows Update PS module...'
	Install-Module PSWindowsUpdate -MinimumVersion 2.2.0.2 -Force
} else {
	if (!$SkipModuleUpdate) {
		Write-Host 'Updating Windows Update PS module...'
		Update-Module -Name PSWindowsUpdate -Force
	}
}

Write-Host 'Importing Windows Update PS module...'
Import-Module PSWindowsUpdate -Force

$WUCommand = 'Get-WindowsUpdate'

if (!$ListOnly) {
	$WUCommand = $WUCommand + ' -Install -AcceptAll'

	if ($RebootAtMidnight -and !$NoAutoReboot) {
		Write-Host 'Reboot at Midnight selected, setting Auto-Reboot on Finish to False.'
		$NoAutoReboot = $true
	}

	if ($NoAutoReboot) {
		$WUCommand = $WUCommand + ' -IgnoreReboot'
	} else {
		$WUCommand = $WUCommand + ' -AutoReboot'
		if ($RebootAtMidnight) {
			Write-Host 'Automatic reboot on finish selected, cancelling Reboot at Midnight.'
			$RebootAtMidnight = $false
		}
	}
} else {
	if ($RebootAtMidnight) {
		Write-Host 'List Only selected.  No reboots will be performed.'
		$RebootAtMidnight = $false
	}
}

if ($MicrosoftUpdate) {
	Write-Host 'We will be checking with Microsoft''s update servers directly.'
	$WUCommand = $WUCommand + ' -MicrosoftUpdate'
} else {
	Write-Host 'We will be checking with the update server indicated in Group Policies (ie: WSUS).'
}

if ($SkipDrivers) {
	Write-Host 'We will not be including Drivers.'
	$WUCommand = $WUCommand + ' -NotCategory "Drivers"'
} else {
	Write-Host 'We will be including Drivers.'
    if ($SkipFirmware) {
        Write-Host 'We will not be including Firmware updates.'
        $WUCommand = $WUCommand + ' -NotTitle "Firmware"'
    } else {
        Write-Host 'We will be including Firmware updates.'
    }
}

Write-Host 'Starting Windows Update Check/Install...'
Write-Host ('-> Command used: "{0}"' -f $WUCommand)
Invoke-Expression $WUCommand

if (!$ListOnly -and $RebootAtMidnight) {
	Write-Host 'Scheduling reboot for midnight tonight...'
	$exeArgs = '/AcceptEULA /R /F /T 00:00'
	Start-Process -FilePath ('{0}\psshutdown.exe' -f $PSScriptRoot) -ArgumentList $exeArgs -Wait -NoNewWindow
}

Write-Host 'Done.'
}
install_updates -MicrosoftUpdate -SkipFirmware -SkipDrivers -NoAutoReboot -Confirm:$False
