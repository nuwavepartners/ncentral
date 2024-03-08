<#
.SYNOPSIS
Installs or reinstalls the N-Central Agent and Take Control (TC) components on Windows devices.

.DESCRIPTION
This script automates the installation or reinstallation of the N-Central Agent and Take Control (TC) components. It checks for the existence and status of the agent and TC services and performs installations or repairs as needed. The script supports custom installation parameters like server address, customer ID, and registration token.

.PARAMETERS
-AgentInstaller
    The URL to the N-Central Agent installer executable. Default is 'https://nuwave.link/rmm/WindowsAgentSetup.exe'.

-Server
    The server address for the N-Central Agent to connect to. Default is 'rmm.nuwavepartners.com'. Must resolve to a valid IP address.

-CustomerID
    The customer ID used for the N-Central Agent installation. Must be a valid integer.

-RegistrationToken
    The registration token used for the N-Central Agent installation. Must be a valid GUID.

-ForceReinstall
    Forces the reinstallation of the N-Central Agent and Take Control components regardless of their current state.

-LocalFile
    Optional. Specifies a local file path for the installer to use instead of downloading it. If not provided, the script downloads the installer.

.EXAMPLE
PS> .\InstallNcentralAgent.ps1 -CustomerID '12345' -RegistrationToken 'A1B2C3D4-E5F6-7890-GH12-3I4J5K6LMNOP'

This example installs or reinstalls the N-Central Agent and Take Control components with the specified customer ID and registration token.

.NOTES
Requires PowerShell 3.0 or later and must be run as an administrator.
#Requires -Version 3 -RunAsAdministrator

.AUTHOR
Email: chris.stone@nuwavepartners.com
#>
#Requires -Version 3 -RunAsAdministrator

Param (
	[ValidateScript({
			[System.Net.Dns]::Resolve($Hostname)
		})]
	[string]	$Server,
	[ValidateScript({
			[int32]::TryParse($_, [ref]([int32] $outputInt))
		})]
	[string]	$CustomerID,
	[ValidateScript({
			[guid]::TryParse($_, [ref]([guid]$outputGuid))
		})]
	[string]	$RegistrationToken,
	[ValidateScript({
			[version]::TryParse($_, [ref]([version]$outputVersion))
	})]
	[string]	$AgentVersion,

	[switch]	$ForceReinstall
)

################################## THE SCRIPT ##################################

#### N-Central Agent

$AgentBinPath = Join-Path ${env:ProgramFiles(x86)} 'N-Able Technologies\Windows Agent\bin\agent.exe'
$AgentServiceName = 'Windows Agent Service'

$ReinstallAgent = $false

# Checks
Try {
	$CheckAgentBin = Test-Path -PathType Leaf -Path $AgentBinPath -ErrorAction SilentlyContinue
	$AgentService = Get-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
} Catch {
	Throw $_
}

# Agent binary not found
if (-not $CheckAgentBin) {
	Write-Output 'Agent Not Installed'
	$ReinstallAgent = $true
}
# Agent service
if ($null -ne $AgentService) {
	if ($AgentService.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
		Write-Output ('Agent Service Found and Running')
	} else {
		Write-Output ('Agent Service Found Stopped, Starting...')
		try {
			Start-Service -Name $AgentServiceName -ErrorAction Stop
			Write-Output ('Agent Service Started')
		} catch {
			Write-Output ('Agent Service Found but Could Not Start')
			Throw $_
		}
	}
} else {
	Write-Output 'Agent Service Not Found'
	$ReinstallAgent = $true
}

# Do the Install
if ($ForceReinstall -or $ReinstallAgent) {

	$Downloaded = $false
	if ([string]::IsNullOrEmpty($LocalFile)) {
		$LocalFile = Join-Path $env:TEMP $AgentInstaller.Segments[-1]
		Start-BitsTransfer -Source ('https://' + $Server + '/download/' + $AgentVersion + '/winnt/N-central/WindowsAgentSetup.exe') -Destination $LocalFile
		$Downloaded = $true
	}

	$AgentInstallerArgs = @(
		'/S', ('/V" /qn CUSTOMERID={0} REGISTRATION_TOKEN={1} CUSTOMERSPECIFIC=1 SERVERADDRESS={2}"' -f `
				$CustomerID, $RegistrationToken, $Server)
	)
	$R = Start-Process -FilePath $LocalFile -ArgumentList $AgentInstallerArgs -Wait -PassThru

	Write-Output $R.ExitCode
	If ($R -eq 0) {
		Write-Output 'Agent Installation Successful'
	}

	if ($Downloaded) {
		Remove-Item -Path $LocalFile
	}
}

#### N-Central Take Control

$TCBinPath = Join-Path ${env:ProgramFiles(x86)} "\BeAnywhere Support Express\GetSupportService_N-Central\BASupSrvc.exe"
$TCServiceName = @('BASupportExpressStandaloneService_N_Central', 'BASupportExpressSrvcUpdater_N_Central')

$ReinstallTC = $false

# Checks
# TC binary not found
if (-not (Test-Path -PathType Leaf -Path $TCBinPath -ErrorAction SilentlyContinue)) {
	Write-Output 'TC Not Installed'
	$ReinstallTC = $true
}
# TC service
Foreach ($ServiceName in $TCServiceName) {
	Try {
		$TCService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
	} Catch {
		Throw $_
	}
	if ($null -ne $TCService) {
		if ($TCService.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
			Write-Output ('TC Service Found and Running {0}' -f $ServiceName)
		} else {
			Write-Output ('TC Service Found Stopped, Starting...')
			try {
				Start-Service -Name $ServiceName -ErrorAction Stop
				Write-Output ('TC Service Started')
			} catch {
				Write-Output ('TC Service Found but Could Not Start')
				Throw $_
			}
		}
	} else {
		Write-Output 'TC Service Not Found'
		$ReinstallTC = $true
	}
}

#Do the TC Install
if ($ForceReinstall -or $ReinstallTC) {

	Write-Output 'Installing Take Control'
	[version] $AgentVersion = (Get-ItemProperty -Path $AgentBinPath -Name 'VersionInfo').VersionInfo.FileVersion
	[xml] $NCentralSIS = (New-Object System.Net.WebClient).DownloadString('https://sis.n-able.com/GenericFiles.xml')
	If ($null -eq $NCentralSIS) { Throw 'Unable to download N-Able SIS Configuration'}

	$TCInstaller = $null
	Foreach ($Range in $NCentralSIS.GenericFiles.Range) {
		If (($Range.Minimum -lt $AgentVersion) -and ($Range.Maximum -gt $AgentVersion)) {
			[uri] $TCInstaller = ($Range.GenericFile | Where-Object { $_.Type -eq 'MSPAInstaller' }).Name
		}
	}
	If ($null -eq $TCInstaller) { Throw 'No version of TC Found for Agent Version' }

	$TCLocalFile = Join-Path $env:TEMP $TCInstaller.Segments[-1]
	Start-BitsTransfer -Source $TCInstaller -Destination $TCLocalFile

	$TCInstallerArgs = @('/S')
	$R = Start-Process -FilePath $TCLocalFile -ArgumentList $TCInstallerArgs -Wait -PassThru

	Write-Output $R.ExitCode
	If ($R -eq 0) {
		Write-Output 'TC Installation Successful'
	}

	Remove-Item -Path $TCLocalFile -ErrorAction SilentlyContinue
}
