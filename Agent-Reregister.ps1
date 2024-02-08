<# 
.NOTES 
	Author:			Chris Stone <chris.stone@nuwavepartners.com>
	Date-Modified:	2020-12-02 13:35:44
.SYNOPSIS
	Reregistered existing Agents, or installs new
#>

$NewCustomerID = "514" # Gleaners
$RegToken = '99f7538e-9e50-789f-4db8-25dad5801561'		# Expires 2020-12-31 11:59 PM.

$This_CS = Get-CimInstance -ClassName Win32_ComputerSystem

# Self-elevate the script if required
Write-Host "Checking for Elevated Privileges"
If (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
	If ([version](Get-CimInstance -Class Win32_OperatingSystem).Version -ge [version]"6.0") {
		$CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
		Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList $CommandLine
		Exit
	}
} Else {
	Write-Host "`tFound"
}

Write-Host "Checking for existing Agent"
#If ((Get-Service "Windows Agent Service" -ErrorAction SilentlyContinue).Count) {	# TODO Fix reregistration
If ($false) {
	
	Write-Host "`tFound"

	@('Windows Agent Service',
		'Windows Agent Maintenance Service') |% {
		Stop-Service $_
	}

	Write-Host "Updating Agent Configuration"
	$fpAplConf = "C:\Program Files (x86)\N-able Technologies\Windows Agent\config\ApplianceConfig.xml"
	($xml = New-Object System.Xml.XmlDocument).Load($fpAplConf)

	$SettingsToChange = @(
		@{ "Node" = "//ApplianceID"; 			"Text" = "-1" },
		@{ "Node" = "//CheckerLogSent";			"Text" = "False" },
		@{ "Node" = "//CustomerID";				"Text" = $NewCustomerID },
		@{ "Node" = "//CompletedRegistration";	"Text" = "False" },
		@{ "Node" = "//URL";					"Text" = "aHR0cHM6Ly9ybW0ubnV3YXZlcGFydG5lcnMuY29tLDE3Mi4yNS4wLjIwMC9ib3NoL2Jvc2gv" }
	)

	Foreach ($Setting in $SettingsToChange) {
		$xml.SelectSingleNode($Setting.Node).InnerText = $Setting.Text
	}

	$xml.Save($fpAplConf)
	Write-Host "`tDone"
	
	Write-Host "Running Cleanup Commands"
	$R = Start-Process -FilePath "C:\Program Files (x86)\N-able Technologies\Windows Agent\bin\NcentralAssetTool.exe" -ArgumentList "-d" -PassThru -Wait
	Write-Host "AssetTool: $($R.ExitCode)"
	$R = Start-Process -FilePath "C:\Program Files (x86)\BeAnywhere Support Express\GetSupportService_N-Central\uninstall.exe" -ArgumentList "/S" -PassThru -Wait
	Write-Host "TakeControl: $($R.ExitCode)"
	Remove-Item -Path ($env:ProgramData + "\N-Able Technologies\Windows Agent\Config") -Recurse
	Remove-Item -Path ($env:ProgramData + "\N-Able Technologies\Windows Software Probe\Config") -Recurse -Ea SilentlyContinue
	Remove-Item -Path ($env:ProgramData + "\N-Able Technologies\Windows Agent\config\ConnectionString_Agent.xml") -Ea SilentlyContinue

	Start-Service 'Windows Agent Service'

} Else {

	Write-Host "`tNo Agent"

	$AgentURL = 'http://nuwave.link/rmm/NCentral-Agent_2020.1.3.381.exe'
	$AgentUNC = ("\\{0}\NETLOGON\{1}" -f $This_CS.Domain, 'NCentral-Agent_2020.1.3.381.exe')
	$TempFile = ($env:TEMP + "\RMM_Agent.exe")

	If (Test-Path -Path $AgentUNC) {
		Write-Host "`tFound LAN Agent"
		Copy-Item -Path $AgentUNC -Destination $TempFile
	} else {
		Write-Host "`tDownloading Agent"
		Invoke-WebRequest -Uri $AgentURL -OutFile $TempFile
	}
	
	$ArgList = '/s /v"/qn CUSTOMERID={0} REGISTRATION_TOKEN={1} CUSTOMERSPECIFIC=1 SERVERPROTOCOL=HTTPS SERVERADDRESS={2} SERVERPORT=443"' -f $NewCustomerID, $RegToken, 'rmm.nuwavepartners.com'
	Write-Host "`tInstalling Agent"
	$R = Start-Process -FilePath $TempFile -ArgumentList $ArgList -PassThru -Wait

	Write-Host "Agent Installation: $($R.ExitCode)"

}