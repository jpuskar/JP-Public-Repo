#Provision-AMT.ps1
# johnpuskar@gmail.com
# puskar.4@osu.edu
# http://windowsmasher.wordpress.com
# b6 - 03.17.2013

#This script will attempt to provison an AMT client using the provided`
# RCS Server

#This script will write a "network settings file" for use with the'
# Intel AMT Configurator (ACUConfig.exe) on systems that are assigned'
# a static IP Address. It will export the first non-private IPv4 address.
#

$logFilePath = "\\winfs\logs\scripts\provision-amt\"

$gRcsServerFQDN = $null
$gRcsServerFQDN = "sccm-chm1.chemistry.ohio-state.edu"
$gStaticProfileName = $null
$gStaticProfileName = "CHM-RConfig-static"
$gDhcpProfileName = $null
$gDhcpProfileName = "CHM-RConfig-dhcp"

$gSitecode = $null
$gSitecode = "chm"

$scriptpath = $MyInvocation.MyCommand.Path
$gWorkingDir = Split-Path $scriptpath

Function Get-NetInfo {
	#IPAddr
	$targetAdapter = $null
	$adaptFound = $null
	$adaptFound = $false
	$adapterConfigs = $null
	$adapterConfigs = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE -ComputerName .
	$adapterConfigs | % {
		#Look for an IPv4 address that's internet-facing
		$adaptFound = $false
		$_.IPAddress | % {If($_ -notmatch ":" -and $_ -notlike "10.*" -and $_ -notlike "192.168*" -and $_ -notlike "172.*"){$adaptFound = $True}}
		If($adaptFound -eq $true)
			{$targetAdapter = $_}
	}
	
	If($targetAdapter -ne $null)
		{
			$tgtIPv4 = $null
			$tgtSubnet = $null
			$i = 0
			$targetAdapter | % {
				While($i -le $_.IPAddress.Count -and $foundIP -ne $true)
					{
						$curIP = $_.IPAddress[$i]
						If($curIP -notmatch ":" -and $curIP -notlike "10.*" -and $curIP -notlike "192.168*" -and $curIP -notlike "172.*")
							{Break}
						$i++
					}
				$tgtIPv4 = $_.IPAddress[$i]
				$tgtSubnet = $_.IPSubnet[$i]
				[string]$tgtGateway = $_.DefaultIpGateway
				[string]$tgtDNS1 = $_.DNSServerSearchOrder[0]
				[string]$tgtDNS2 = $_.DNSServerSearchOrder[1]
				[string]$fqdn = ("$env:computername.$env:userdnsdomain").ToLower()
			}
		}
	
	$netInfo = $null
	If($targetAdapter -ne $null)
		{
			$netInfo = New-Object System.Object
			$netInfo | add-member -type noteProperty -name "AmtIpAddress" -value $tgtIPv4
			$netInfo | add-member -type noteProperty -name "AmtGateway" -value $tgtGateway
			$netInfo | add-member -type noteProperty -name "AmtSubnet" -value $tgtSubnet
			$netInfo | add-member -type noteProperty -name "AmtDns" -value $tgtDNS1
			$netInfo | add-member -type noteProperty -name "AmtSecondaryDns" -value $tgtDNS2
			$netInfo | add-member -type noteProperty -name "fqdn" -value $fqdn
		}
	
	return $netInfo
	
}

Function Write-NetworkSettingsFile($NetInfo) {
	#XML Reference: http://www.tehhuman.com/creating-xml-documents-from-powershell/
	# Set the File Name
	$filePath = $gWorkingDir + "\NetworkSettings.xml"
	
	# Create The Document
	$XmlWriter = New-Object System.XMl.XmlTextWriter($filePath,[Text.Encoding]::UTF8)
	
	# Set The Formatting
	$xmlWriter.Formatting = "Indented"
	$xmlWriter.Indentation = "4"
	
	# Write the XML Decleration
	$xmlWriter.WriteStartDocument()
	
	# Write Root Element
	$xmlWriter.WriteStartElement("NetworkSettings")
	$xmlWriter.WriteElementString("CurrentAmtAddress",$NetInfo.fqdn)
	$xmlWriter.WriteElementString("NewAmtFQDN",$NetInfo.fqdn)
	
	# Write the Document
	$xmlWriter.WriteStartElement("AmtIP")
	$xmlWriter.WriteElementString("AmtIPAddress",$NetInfo.AmtIpAddress)
	$xmlWriter.WriteElementString("AmtSubnet",$NetInfo.AmtSubnet)
	$xmlWriter.WriteElementString("AmtGateway",$NetInfo.AmtGateway)
	$xmlWriter.WriteElementString("AmtDNS",$NetInfo.AmtDNS)
	$xmlWriter.WriteElementString("AmtSecondaryDNS",$NetInfo.AmtSecondaryDNS)
	$null = $xmlWriter.WriteEndElement # <-- Closing Servers
	
	# Write Close Tag for Root Element
	$null = $xmlWriter.WriteEndElement # <-- Closing RootElement
	
	# End the XML Document
	$xmlWriter.WriteEndDocument()
	
	# Finish The Document
	$xmlWriter.Finalize
	$null = $xmlWriter.Flush
	$xmlWriter.Close()
}

Function Run-AMTConfigure {
	#Check for a static IP
	$bStaticIP = $null
	$bStaticIP = $false
	$dhcpAdapters = $null
	$dhcpAdapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter DHCPEnabled=TRUE -ComputerName . | Where{$_.IPAddress -ne $null}
	$model = (gwmi Win32_ComputerSystem).model
	$model = $model.replace(" ","").toLower()
	If($dhcpAdapters -eq $null -or $model -eq "optiplex960") {
			#Write-Host "No DHCP Adapters found."
			$bStaticIP = $true
	}
	
	#write the network settings file
	If($bStaticIP -eq $true) {
		$netInfo = $null
		$netInfo = Get-NetInfo
		If($netInfo -eq $null){}
		Else
		{
			#Write-host -f cyan "Writing a network settings file."
			Write-NetworkSettingsFile $netInfo
		}
	}
	
	#run the configurator
	$cmd = ".\ACUConfig.exe"
	$cmdArgs = $null
	$cmdArgs = "/output console ConfigViaRCSOnly " + $gRcsServerFQDN
	If($bStaticIP -eq $false) {
		$cmdArgs += " " + $gDhcpProfileName
	}
	Else {
		$netSettingsFile = $gWorkingDir + "\NetworkSettings.xml"
		$cmdArgs += " " + $gStaticProfileName
		$cmdArgs += " /NetworkSettingsFile " + $netSettingsFile
	}
	
	$msg = "Running cmd: " + $cmd + " " + $cmdArgs
	write-host -f yellow $msg
	Start-Process $cmd -ArgumentList $cmdArgs -NoNewWindow -Wait
}

Function Run-AMTSystemDiscovery {
	#run the configurator
	$cmd = ".\ACUConfig.exe"
	$cmdArgs = $null
	$cmdArgs += "/output console SystemDiscovery"
	$msg = "Running cmd: " + $cmd + " " + $cmdArgs
	write-host -f yellow $msg
	Start-Process $cmd -argumentList $cmdArgs -NoNewWindow -Wait
}

Function Run-SCCM-HW-Inv {
	#Binding SMS_Client wmi class remotely.... 
	$SMSCli = [wmiclass] "\\.\root\ccm:SMS_Client"
	Write-Host -f yellow "Invoking SCCM Hardware Inventory"
	$check = $SMSCli.TriggerSchedule("{00000000-0000-0000-0000-000000000001}")
}

Function Invoke-SCCM-AMTDiscovery {
	$msg = "Invoking an SCCM AMT Discovery on this system."
	Write-host -f yellow $msg
	$hostname = ("$env:computername.$env:userdnsdomain").ToLower()
	$hostQuery = "select resourceid from sms_r_system where ResourceNames like """ + $hostname + """"
	$namespace = "root\sms\site_" + $gSiteCode
	
	$oAmtResourceID = Get-WmiObject -query $hostQuery -Namespace $namespace -computername $gRcsServerFQDN
	$amtResourceID = $oAmtResourceID.ResourceID
	
	[string]$WmiString = "\\" + $gRcsServerFQDN + "\" + $namespace + ":SMS_Collection"
	$SccmCollectionClass = [wmiclass]$wmiString
	$result = $SccmCollectionClass.AMTOperateForMachines("CHM0008A",@($amtResourceID),8,0)
	#write-host -f green $result
}

Function Extract-MESetup {
	$bFail = $false
	$bFound = $null
	$bFound = $false
	
	#get amt version by sccm inventory
	$hostname = ("$env:computername.$env:userdnsdomain").ToLower()
	$hostQuery = "select * from sms_r_system where ResourceNames like """ + $hostname + """"
	$namespace = "root\sms\site_" + $gSiteCode
	$oAmtResource = Get-WmiObject -query $hostQuery -Namespace $namespace -computername $gRcsServerFQDN
	If($oAmtResource.AMTFullVersion -eq $null){$bFound = $false}
	Else{bFound = $true; [int]$amtVer = $oAmtResource.AMTFullVersion.Substring(0,1)}
	
	#if blank, fall back to a map
	$amtVer = $null
	If($bFound -eq $false)
		{
			$model = (gwmi win32_computerSystem).model
			[string]$model = $model.ToLower().replace(" ","")
			Switch($model) {
				"latitudee4200" {$amtVer = 4}
				"optiplex760" {$amtVer = 5}
				"optiplex780" {$amtVer = 5}
				"optiplex960" {$amtVer = 5}
				"optiplex980" {$amtVer = 6}
				"optiplex990" {$amtVer = 7}
				"optiplex9010" {$amtVer = 8}
			}
		}
	
	$fileName = $null
	Switch($amtVer) {
		4 {$fileName = "Intel-ME4.exe"}
		5 {$fileName = "Intel-ME5.exe"}
		6 {$fileName = "Intel-ME6.exe"}
		7 {$fileName = "Intel-ME7.exe"}
		8 {$fileName = "Intel-ME8.exe"}
		Default {$bFail = $True}
	}
	
	If($bFail -eq $false) {
	$cmd = $null
	$cmd = ".\" + $fileName
	$msg = "Extracting the Intel MEI version " + $amtVer + " setup with command: """ +  $cmd + """."
	write-host -f yellow $msg
	Start-Process $cmd -NoNewWindow -Wait
	}
	
	If($bFail -eq $true){$retval = $false}
	Else{$retval = $true}
	Return $retval
}

Function Fix-DriverMissing {
	$bFail = $false
	$bDriverInstalled = $false
	#Test for the Intel Driver
	$arrDriverList = $null
	$arrDriverList = gwmi Win32_PNPEntity | where {$_.Caption -like "intel*"} | % {$_.Caption}
	$arrDriverList | % {
		If($_ -like "Intel(R) Management Engine Interface") {$bDriverInstalled = $true}
	}
	
	#Test for LMS.exe
	$bLMSNeeded = $false
	$progFiles32 = $null
	If((Test-Path "C:\Program Files (x86)") -eq $true) {$progFiles32 = "C:\Program Files (x86)\"}
	Else {$progFiles32 = "C:\Program Files\"}
	$LMSPath1 = $progFiles32 + "Intel\Intel(R) Management Engine Components\LMS\lms.exe"
	$LMSPath2 = $progFiles32 + "Intel\AMT\lms.exe"
	If((Test-Path $LmsPath1) -eq $true -or (Test-Path $LMSPath2) -eq $true){}
	Else{$bLmsNeeded = $true}	
	
	#prep and build the cmd line
	$bRunInstall = $false
	If($bLmsNeeded -eq $true -or $bDriverInstalled -eq $false) {
		$bRunInstall = $true
		$bAction = $null
		$bAction = $false
		$bAction = Extract-MESetup
		If($bAction -eq $false) {
			$bRunInstall -eq $false
			$bFail = $true
			Write-host -f magenta "Intel MEI Driver needed, but setup path not found for this AMT version."
		}
		$cmd = $null
		$cmd = ".\Intel-MEI\setup.exe"
		$cmdArgs = $null
		$cmdArgs = "/s"
	}
	
	If($bLMSNeeded -eq $true -and $bDriverInstalled -eq $true)
		{$cmdArgs += " -nodrv"}
	
	If($bRunInstall -eq $true) {
		$msg = "Installing Intel MEI with command: " + $cmd + " " + $cmdArgs
		write-host -f yellow $msg
		Start-Process $cmd -argumentList $cmdArgs -NoNewWindow -Wait
		Sleep -s 15
	}
	
	If($bRunInstall -eq $true -and (Test-Path ".\Intel-SOL") -eq $true) {
		$cmd = ".\Intel-SOL\setup.exe"
		$cmdArgs = $null
		$cmdArgs = "/s"
		$msg = "Installing Intel SOL with command: " + $cmd + " " + $cmdArgs
		write-host -f yellow $msg
		Start-Process $cmd -argumentList $cmdArgs -NoNewWindow -Wait
		Sleep -s 15
	}
	
	If($bRunInstall -eq $true -and $bDriverInstalled -eq $false) {
		Sleep -s 30
		$cmd = ".\devcon.exe"
		$cmdArgs = "rescan"
		$msg = "Rescanning hardware devices with the command: " + $cmd + " " + $cmdArgs
		Write-Host -f yellow $msg
		Start-Process $cmd -ArgumentList $cmdArgs -NoNewWindow -Wait
		Sleep -s 90
	}
	
	If($bFail -eq $true){$retval = $false}
	Else{$retval = $true}
	Return $retval
}

#Clear previous logs
del *.log -force

#Do Stuff!
$bAction = $null
$bAction = Fix-DriverMissing
If($bAction -eq $true) {
	Run-AMTConfigure
	sleep -s 120
	Run-AMTSystemDiscovery
	Run-SCCM-HW-Inv
	Invoke-SCCM-AMTDiscovery
}

#Upload log
If(Test-Path $logFilePath) {}
Else {mkdir $logFilePath}
copy .\*.log $logFilePath -force