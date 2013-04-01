#Write-Host "Running Script"
#use $args when testing manually, use $Param in opsmgr scripting\deployment

###TODO -- check args, use if fails
Param($xmlText)
$error.clear()
$fail = $false
$scriptName = "Process-Syslogs.ps1 b17 (auto)"

$script:debugLevel = 4									#verbosity
$script:blnWriteToScreen = $false				#write to the screen
$script:blnWriteToOpsMgrLog = $true			#write to the opsmgr log

$opsmgrAPI = New-Object -comObject 'MOM.ScriptAPI'

#$xmlText = $args[0]
$xml = [xml]($xmlText)

Function Get-RMSServer
	{
		$RMSServer = $null
		
		$machineKey = "HKLM:\\SOFTWARE\Microsoft\Microsoft Operations Manager\3.0\Machine Settings"
		If((Test-Path $machineKey) -eq $true)
			{
				$objKey = Get-ItemProperty -path:$machineKey -name:"DefaultSDKServiceMachine" -ErrorAction:SilentlyContinue
				If($objKey -ne $null -and $objKey -ne "")
					{$RMSServer = $objKey.DefaultSDKServiceMachine}
			}
		
		If($RMSServer -eq $null -or $RMSServer -eq "")
			{
				#write-host -f green "ehy"
				$MgmtGroupsKey = $null
				$MgmtGroupsKey = "HKLM:\\SOFTWARE\Microsoft\Microsoft Operations Manager\3.0\Agent Management Groups"
				If((Test-Path $mgmtGroupsKey) -eq $false)
					{
						$msg = "Failed to process a syslog event; can't find the RMS Server name in registry"
						Write-Out $msg 2
					}
				Else
					{
						$mgmtGroups = $null
						$mgmtGroups = GCI $MgmtGroupsKey
						#write-host -f cyan $MgmtGroupsKey
						
						If($mgmtGroups -is [array])
							{$strMgmtGroupKey = $mgmtGroups[0].Name}
						Else
							{$strMgmtGroupKey = $mgmtGroups.Name}
						
						$strMgmtGroupKey = $strMgmtGroupKey -replace("HKEY_LOCAL_MACHINE","HKLM:\") 
						#write-host -f yellow $strMgmtGroupKey
						
						$strMachineKey = $null
						$strMachineKey = $strMgmtGroupKey + "\Parent Health Services\0"
						$RMSServer = $null
						$RMSServer = (Get-ItemProperty -path:$strMachineKey -name:"NetworkName" -ErrorAction:SilentlyContinue).NetworkName
					}
			}
		#write-host -f yellow "RMSServer: $RMSServer"
		Return $RMSServer
	}

Function Resolve-IP($IPAddr)
	{
		Trap{}
		$hostname = $IPAddr
		$hostname = [System.Net.Dns]::GetHostEntry($IPAddr).Hostname
		Return $hostname
	}

Function Resolve-Facility($xmlFacility)
	{
		$strFacility = $null
		Switch($xmlFacility)
			{
				Default {$strFacility = $null}
				0 {$strFacility = "Kernel"}
				1 {$strFacility = "User-Level"}
				2 {$strFacility = "Mail System"}
				3 {$strFacility = "System Daemons"}
				4 {$strFacility = "SecurityAuth4"}
				5 {$strFacility = "syslogd"}
				6 {$strFacility = "lps"}
				7 {$strFacility = "nns"}
				8 {$strFacility = "UUCP"}
				9 {$strFacility = "clock9"}
				10 {$strFacility = "SecurityAuth10"}
				11 {$strFacility = "FTP"}
				12 {$strFacility = "NTP"}
				13 {$strFacility = "LogAudit"}
				14 {$strFacility = "LogAlert"}
				15 {$strFacility = "clock15"}
			}
		Return $strFacility
	}

Function Resolve-Severity($xmlSeverity)
	{
		$strSeverity = $null
		Switch($xmlSeverity)
			{
				Default {$strFacility = $null}
				0 {$strSeverity = "Emergency"}
				1 {$strSeverity = "Alert"}
				2 {$strSeverity = "Critical"}
				3 {$strSeverity = "Error"}
				4 {$strSeverity = "Warning"}
				5 {$strSeverity = "Notice"}
				6 {$strSeverity = "Information"}
				7 {$strSeverity = "Debug"}
				8 {$strSeverity = "Random"}
			}
		Return $strSeverity
	}

Function Get-VIHostnamesAndGUIDs
	{
		$hshHostnamesAndGUIDs = $null
		$hshHostnamesAndGUIDs = @{}
		
		$strClassID = $null
		$strClassID = "JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host"
		
		$objClass = $null
		$objClass = Get-MonitoringClass -name $strClassID -path "OperationsManagerMonitoring::"
		If($objClass -is [array])
			{$objClass = $objClass[0]}
		If($objClass -eq $null)
			{
				$msg = "Unable to lookup the class """ + $strClassID + """."
				Write-Out $msg 2
			}
		
		$arrObjHosts = Get-MonitoringObject -monitoringclass $objClass -path "OperationsManagerMonitoring::"
		If($objClass -eq $null)
			{
				$msg = "Unable to lookup the objects of class """ + $strClassID + """."
				Write-Out $msg 2
			}
		Else
			{
				Foreach($objHost in $arrObjHosts)
					{
						$strHostname = $objHost.DisplayName
						If($hshHostnamesAndGUIDs.Keys -contains $strHostname){}
						Else
							{
								$strGUID = $objHost.Id
								$hshHostnamesAndGUIDs.Add($strHostname,$strGUID)
							}
					}
			}
		Return $hshHostnamesAndGUIDs
	}

Function Write-Out($msg,$severity)
	{
		$intLevel = 4
		If($intLevel -eq $null)
			{$intLevel = 4}
		
		If($severity -eq $null)
			{$severity = 0}
		
		If($intLevel -le $script:debugLevel)
			{
				If($script:blnWriteToScreen -eq $true)
					{
						Switch($severity)
							{
								0 {$color = "white"}
								1 {$color = "yellow"}
								2 {$color = "magenta"}
							}
						Write-Host -f $color $msg
					}
				Else{}
				If($script:blnWriteToOpsMgrLog -eq $true)
					{
						If($severity -eq 1){$severity = 2}
						ElseIf($severity -eq 2){$severity = 1}
						$opsmgrAPI.LogScriptEvent($scriptName,0,$severity,$msg)
					}
				Else{}
			}
	}

#load-snapins
Function Load-Snapins
	{
		$fail = $null
		$fail = $false
		$snapin = "Microsoft.EnterpriseManagement.OperationsManager.Client"
		$msg = "Script is attempting to load snap-in: """ + $snapin + """."
		Write-Out $msg
		$snapinTest = $null
		$snapinTest = Get-PSSnapin $snapin -registered -ea silentlycontinue
		If($snapinTest -ne $null)
			{
				$msg = "The required snap-in is installed on this system: """ + $snapin + """. Adding the snap-in."
				Write-Out $msg
				$snapinTest = $null
				$snapinTest = Get-PSSnapin $snapin -ea silentlycontinue
				If($snapinTest -eq $null)
					{$blnAdded = Add-PSSnapin $snapin}
				Else
					{}
			}
		Else
			{
				$fail = $true
				$msg = "Required Snap-In is not installed on this system: """ + $snapin + """."
				Write-Out $msg 2
			}
		
		If($fail -eq $false)
			{
				$snapinTest = $null
				$snapinTest = Get-PSSnapin $snapin
				if($snapinTest -eq $null)
					{
						$fail = $true
						$msg = "Script didn't complete loading snap-ins; could not add the snapin: """ + $snapin + """."
						Write-Out $msg 2
					}
			}
		
		If($fail -eq $false)
			{$retval = $true}
		Else
			{$retval = $false}
		Return $retval
	}


### MAIN LOOP
$scriptUser = $env:username
$msg = "Script starting; running as """ + $scriptUser + """."
Write-Out $msg

$msg = "Original XML Input Data: " + $xmlText
Write-Out $msg

$blnLoaded = Load-Snapins
$opsmgrRMS = Get-RMSServer
If($opsmgrRMS -eq $null -or $opsmgrRMS -eq "")
	{
		$msg = "Could not get the RMS server name from the registry."
		Write-Out $msg
		$fail = $true
	}

If($fail -eq $false)
	{
		$msg = "Connecting to the management server """ + $opsmgrRMS + """."
		Write-Out $msg
		$strConnect = New-ManagementGroupConnection $opsmgrRMS
		$msg = "Connection result: """ + $strConnect + """."
		Write-Out $msg
	}

If($fail -eq $false)
	{
		#create pbag
		$api = New-Object -comObject 'MOM.ScriptAPI'
		$bag = $api.CreatePropertyBag()
		$hshValues = $null
		$hshValues = @{}
		
		#Process Hostname and IPAddr
		$xmlHostname = $xml.dataitem.eventdata.dataitem.HostName
		$strIPRegex = "\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"
		If($xmlHostname -match $strIPRegex)
			{
				$bagLoggingComputer = Resolve-IP $xmlHostname
				#$bag.AddValue("HostName",$bagLoggingComputer)
				$hshValues.Add("HostName",$bagLoggingComputer)
			}
		#$bag.AddValue("IPAddress",$xmlHostname)
		$hshValues.Add("IPAddress",$xmlHostname)
		
		#process opsmgr_LoggingComputer
		If($bagLoggingComputer -ne $null)
			{
				$strLoggingComputer = $bagLoggingComputer
				$strLoggingComputer = $strLoggingComputer.ToLower()
			}
		Else
			{
				$xmlHostname = $xml.dataitem.eventdata.dataitem.HostName
				$strLoggingComputer = $xmlHostname
			}
		#$bag.AddValue("opsmgr_LoggingComputer",$strLoggingComputer)
		$hshValues.Add("opsmgr_LoggingComputer",$strLoggingComputer)
		
		
		#Process Source GUID
		$hshHostnamesAndGUIDs = $null
		$hshHostnamesAndGUIDs = Get-VIHostnamesAndGUIDs
		$arrKeys = $null
		$arrKeys = $hshHostnamesAndGUIDs.Keys
		
		$strHosts = $null
		$OFS = ","; $strHosts = $arrKeys; $OFS=" "
		$msg = "Found the following vCenter hosts: " + $strHosts + "."
		write-out $msg
		If($arrKeys -contains $strLoggingComputer)
			{
				$strSourceID = $null
				$strSourceID = $hshHostnamesAndGUIDs.$strLoggingComputer
				#$bag.AddValue("EventOriginId",$strSourceID)
				$hshValues.Add("CustomMonitoredObjectGUID",$strSourceID)
			}
		Else
			{
				#$GUID = Get-GUIDofCurrentSystem
				$fail = $true
				$msg = "Cancelled processing a syslong; no vCenter host was found matching the syslog hostname """ + $strLoggingComputer + """."
				Write-Out $msg 2
			}
	}

If($fail -eq $false)
	{
		#Process Facility
		$xmlFacility = $xml.dataitem.eventdata.dataitem.Facility
		If($xmlFacility -is [system.array]){$xmlFacility = $xmlFacility[0]}
		#$bag.AddValue("Facility",$xmlFacility)
		$hshValues.Add("Facility",$xmlFacility)
		$strFacility = Resolve-Facility $xmlFacility
		#$bag.AddValue("FacilityName",$strFacility)
		$hshValues.Add("FacilityName",$strFacility)
		
		#Process Severity and SeverityName
		$xmlSeverity = $xml.dataitem.eventdata.dataitem.Severity
		$bag.AddValue("Severity",$xmlSeverity)
		$strSeverity = Resolve-Severity $xmlSeverity
		#$bag.AddValue("SeverityName",$strSeverity)
		$hshValues.Add("SeverityName",$strSeverity)
		
		#Process Priority
		$xmlPriority = $xml.dataitem.eventdata.dataitem.Priority
		#$bag.AddValue("Priority",$xmlPriority)
		$hshValues.Add("Priority",$xmlPriority)
		
		#Process PriorityName
		$xmlPriorityName = $xml.dataitem.eventdata.dataitem.PriorityName
		#$bag.AddValue("PriorityName",$xmlPriorityName)
		$hshValues.Add("PriorityName",$xmlPriorityName)
		
		#Process TimeStamp
		$xmlTimeStamp = $xml.dataitem.eventdata.dataitem.TimeStamp
		#$bag.AddValue("TimeStamp",$xmlTimeStamp)
		$hshValues.Add("TimeStamp",$xmlTimeStamp)
		
		#Process Message
		$xmlMessage = $xml.dataitem.eventdata.dataitem.Message
		#$bag.AddValue("Message",$xmlMessage)
		$hshValues.Add("Message",$xmlMessage)
		
		#Process opsmgr_EventLevel
		#0 = Information
		#1 = Error
		#2 = Warning
		$bagLevel = $null
		$xmlSeverity = $xml.dataitem.eventdata.dataitem.Severity
		If($xmlSeverity -ge 5)
			{$bagLevel = 0}
		ElseIf($xmlSeverity -eq 4)
			{$bagLevel = 2}
		Else
			{$bagLevel = 1}
		#$bag.AddValue("opsmgr_EventLevel",$bagLevel)
		$hshValues.Add("opsmgr_EventLevel",$bagLevel)
		
		#process opsmgr_EventNumber
		$xmlFacility = $xml.dataitem.eventdata.dataitem.Facility
		If($xmlFacility -is [system.array]){$xmlFacility = $xmlFacility[0]}
		#$bag.AddValue("opsmgr_EventNumber",$xmlFacility)
		$hshValues.Add("opsmgr_EventNumber",$xmlFacility)
		
		#Process opsmgr_Channel
		$strLogName = "Syslog\" + $xmlFacility
		If($strFacility -ne $null)
			{$strLogName = $strLogName + " - " + $strFacility}
		$bagLogName = $strLogName
		#$bag.AddValue("opsmgr_Channel",$bagLogName)
		$hshValues.Add("opsmgr_Channel",$bagLogName)
		
		#Process opsmgr_OriginalXMLEvent
		$bagXMLItem = $xml.dataitem.eventdata.dataitem.innerxml
		#$bag.AddValue("opsmgr_OriginalXMLEvent",$bagXMLItem)
		$hshValues.Add("opsmgr_OriginalXMLEvent",$bagXMLItem)
		
		$arrPairs = $null
		$arrPairs = @()
		$keys = $hshValues.Keys
		Foreach($key in $keys)
			{
				$value = $null
				[string]$value = $hshValues.$key
				#write-host -f yellow "key: $key`tvalue: $value"
				$bag.AddValue($key,$value)
				$strValuePair = $key + ":" + $value
				$arrPairs += $strValuePair
			}
		
		$OFS = "  , "; [string]$strValues = $arrPairs; $OFS = " "
		
		#return
		$msg = "Processed a syslog for host """ + $strLoggingComputer + """. Original XML Message: """ + $bagXMLItem + """."
		Write-Out $msg
		$msg = "Final property bag values: " + $strValues
		Write-Out $msg
		$msg = "Errors: " + $error
		Write-Out $msg
		$bag
	}