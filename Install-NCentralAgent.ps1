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
	[uri]	$AgentInstaller = 'https://nuwave.link/rmm/WindowsAgentSetup.exe',

	[ValidateScript({
			[System.Net.Dns]::Resolve($Hostname)
		})]
	[string]	$Server = 'rmm.nuwavepartners.com',
	[ValidateScript({
			[int32]::TryParse($_, [ref]([int32] $outputInt))
		})]
	[string]	$CustomerID,
	[ValidateScript({
			[guid]::TryParse($_, [ref]([guid]$outputGuid))
		})]
	[string]	$RegistrationToken,

	[switch]	$ForceReinstall,
	[string]	$LocalFile = $null
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
		Start-BitsTransfer -Source $AgentInstaller -Destination $LocalFile
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

# SIG # Begin signature block
# MIIF6QYJKoZIhvcNAQcCoIIF2jCCBdYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDtFkeEhp4g3KVE
# JPNBJ2sfz5xv6/gnYoHYkQLabDYDSqCCA0IwggM+MIICJqADAgECAhBZVP3hQBiZ
# h0jf8jC4J2H6MA0GCSqGSIb3DQEBCwUAMDcxNTAzBgNVBAMMLENocmlzIFN0b25l
# IDxjaHJpcy5zdG9uZUBudXdhdmVwYXJ0bmVycy5jb20+MB4XDTIwMDIxODIxNDE0
# MFoXDTI1MDIxODIxNTE0MVowNzE1MDMGA1UEAwwsQ2hyaXMgU3RvbmUgPGNocmlz
# LnN0b25lQG51d2F2ZXBhcnRuZXJzLmNvbT4wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQCg62030xLyXQrQxKA3U1sLBsCbsMuG8CNF0nPBbnx8wy1xSVmR
# NjDj6vHQrrXCEoDPGThIEZfAi2BKu+BiW93pKyYvjH4KluYPaKfpM8DrT1gTfnVJ
# 8W8IMhlO8LptwCV86aLYhcjtLX2Toa130u1uxrr6YrjQ2PQGsG7BUordtbd4vGvD
# etCTtH3il+sHojE1COSwRUQNSY/3xSGm4otjZHg3sGcFK4KzcK4M572nDPXZeuFr
# laBOum+duPBQOo5Za6363tNRpBNff7SNCcftmmA+Wy+Uq8r9/fZR6G9hFm4PB4DF
# dNK5VCkb+qmWa4XaxfEy/EnyZCuk7cH6sJVZAgMBAAGjRjBEMA4GA1UdDwEB/wQE
# AwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUolHkzzvm5ChXKTKR
# wiMqPbfq+qYwDQYJKoZIhvcNAQELBQADggEBAGBrwbmZj03Wz7xZAcuWI1PYheNl
# xks59o5aIUehEKhnc3m3hC7swtL0MLpSwd15ahxoLjKLh7iEsUcvqkUa4Q3DE54s
# lbxfG8eT3YoH8GKpMeZb12dUKk9llqlQpoLzFzaLoixp7dNhi08BIv5LOUTHdM/X
# HDw07N4jzTAVzyTqUnRP4DddH51OQuNzruN2sSt8GmcADQElUaD/yvZ+BKfY8HBv
# HUTOOGpCByR5lqnoRhALnKM+rPlelkA1mWzNkHeVCg3jhNNQSScXtQvymsi07yVF
# zqfBq8h4+dsaIliRAEVDTGk1q7viUiB8bmCv/ht/LU91zehzwiO2EtmzGz8xggH9
# MIIB+QIBATBLMDcxNTAzBgNVBAMMLENocmlzIFN0b25lIDxjaHJpcy5zdG9uZUBu
# dXdhdmVwYXJ0bmVycy5jb20+AhBZVP3hQBiZh0jf8jC4J2H6MA0GCWCGSAFlAwQC
# AQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEIOkoq80JV11zNeQX3QiMxVNnoMD20NGLj8rnpLdOhI8fMA0GCSqG
# SIb3DQEBAQUABIIBABGiMba2osZV03t6C8zc+H0iozzR7ta7vfleDvuROCPD7cG4
# nx74NQbutl4aT3qtbtC8eqse/kCasPXXrdYaBsyfr6JhkTOfV5TB9xhlw2PeRxd3
# Gr5GIsJMf7v6p2PXlolCN35mdO2jP7Woud8KIMNKwVQchBDxUR8dVxH2haA0HRru
# UFSJF5qaiyQO0FEGN+NrudfK98xSZv+ubwJixk4LrotF7eATol6SkC1pR32E8Vpt
# K5DfaBzLfuahStZHNMjQ8bvdSAIigNm54dhPZHUU9ppL2G0Zr79R6PYyHCGMCjq0
# AQIiovZ3PGNgeMLY8ADMHXoy5nqBOJvW5LbHzwM=
# SIG # End signature block
