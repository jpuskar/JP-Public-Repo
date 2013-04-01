#vCenter-CollectEvents.ps1

#TO CHANGE
##change $requiredArgs
##modify parent data
##modify attributes discovered
##modify discovery data class creation MPElement
##change scriptName
##change ending message

##Note -- lookup-vcenterGUID will only work if there's only 1 vcenter object in opsmgr
Param($vCenterServer,$IntervalSeconds,$viUsername,$viPassword)

$error.clear()
$fail = $false
$scriptName = "vCenter-CollectEvents.ps1 b19 (auto)"
$opsmgrAPI = New-Object -comObject 'MOM.ScriptAPI'

#global vars
$script:debugLevel = 4									#verbosity
$script:blnWriteToScreen = $false				#write to the screen
$script:blnWriteToOpsMgrLog = $true			#write to the opsmgr log

###COMMON FUNCTIONS
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

$msg = "Script starting, viUsername: " + $viUsername
write-out $Msg

#parse args
$requiredArgs = $null
$requiredArgs = @()
$requiredArgs += "vCenterServer"
$requiredArgs += "IntervalSeconds"
$requiredArgs += "viUsername"

$failedArgs = $null
$failedArgs = @()
Foreach($requiredArg in $requiredArgs)
	{
		If((Get-Variable $requiredArg -ea silentlycontinue).Value -eq $null)
			{$failedArgs += $requiredArg}
		Else
			{}
	}

If($failedArgs.Count -gt 0)
	{
		$OFS = ","; [string]$strFailedArgs = $failedArgs; $OFS = " "
		$failedArgs = $null
		$msg = "The following required arguments are missing: " + $strFailedArgs
		Write-Out $msg 2
		$fail = $true
	}
Else
	{
		If($intervalSeconds -match "[0-9]+")
			{[int]$intervalSeconds = $intervalSeconds}
		Else
			{
				$msg = "The IntervalSeconds argument passed """ + $intervalSeconds + """ can't be converted to an integer. Failing the script."
				Write-Out $msg 2
				$fail = $true
			}
		
		If($fail -eq $false)
			{
				$arrPairs = $null
				$arrPairs = @()
				Foreach($requiredArg in $requiredArgs)
					{
						$argValue = $null
						$argValue = (Get-Variable $requiredArg -ea silentlycontinue).Value
						$arrPairs += $requiredArg + " : " + $argValue
					}
				$OFS = " , "; [string]$strArgPairs = $arrPairs; $OFS = " "
				$msg = "The following args were passed: " + $strArgPairs
				Write-Out $msg
			}
	}

Function Load-MOMSnapin
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
						$msg = "Error, can't find the RMS Server name in registry"
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

Function Load-VCSnapin
	{
		$fail = $null
		$fail = $false
		$snapin = "VMware.VimAutomation.Core"
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

Function Construct-CSVEventFromEvent($objEvent,$strVIServer,$strGUID)
	{
		#little bit of mapping
		[string]$OM_customMonitoringObjectGUID = $strGUID
		[string]$OM_Channel = "VI Events"
		[string]$OM_loggingComputer = $strVIServer
		[int]$OM_eventNumber = $objEvent.Key
		[string]$OM_levelId = 0
		[string]$OM_Message = $objEvent.FullFormattedMessage
		[string]$OM_Username = $objEvent.UserName
		[string]$OM_PublisherName = "VI Events"
		
		#sudo make me a sammich
		$csvString = $null
		$csvString = """"
		$csvString += $OM_customMonitoringObjectGUID
		$csvString += ""","""
		$csvString += $OM_Channel
		$csvString += ""","""
		$csvString += $OM_loggingComputer
		$csvString += ""","""
		$csvString += $OM_eventNumber
		$csvString += ""","""
		$csvString += $OM_levelId
		$csvString += ""","""
		$csvString += $OM_Message
		$csvString += ""","""
		$csvString += $OM_Username
		$csvString += ""","""
		$csvString += $OM_PublisherName
		
		
		[string]$eventTypeId = $objEvent.EventTypeId
		[string]$severity = $objEvent.severity
		[string]$message = $objEvent.message
		[string]$objectId = $objEvent.objectId
		[string]$objectType = $objEvent.objectType
		[string]$objectName = $objEvent.objectName
		[string]$fault = $objEvent.fault
		[string]$key = $objEvent.key
		[string]$chainId = $objEvent.chainId
		[string]$createdTime = $objEvent.createdTime
		[string]$username = $objEvent.username
		[string]$datacenter = $objEvent.datacenter.name
		[string]$computeResource = $objEvent.computeResource.name
		[string]$strHost = $objEvent.host.name
		[string]$vm = $objEvent.vm.name
		[string]$ds = $objEvent.ds.name
		[string]$net = $objEvent.net.name
		[string]$dvs = $objEvent.dvs.name
		[string]$fullFormattedMessage = $objEvent.fullFormattedMessage
		[string]$changeTag = $objEvent.changeTag
		
		#now add the custom properties
		$csvString += ""","""
		$csvString += $eventTypeId
		$csvString += ""","""
		$csvString += $severity
		$csvString += ""","""
		$csvString += $message
		$csvString += ""","""
		$csvString += $objectId
		$csvString += ""","""
		$csvString += $objectType
		$csvString += ""","""
		$csvString += $objectName
		$csvString += ""","""
		$csvString += $fault
		$csvString += ""","""
		$csvString += $key
		$csvString += ""","""
		$csvString += $chainId
		$csvString += ""","""
		$csvString += $createdTime
		$csvString += ""","""
		$csvString += $username
		$csvString += ""","""
		$csvString += $datacenter
		$csvString += ""","""
		$csvString += $computeResource
		$csvString += ""","""
		$csvString += $strHost
		$csvString += ""","""
		$csvString += $vm
		$csvString += ""","""
		$csvString += $ds
		$csvString += ""","""
		$csvString += $net
		$csvString += ""","""
		$csvString += $dvs
		$csvString += ""","""
		$csvString += $fullFormattedMessage
		$csvString += ""","""
		$csvString += $changeTag
		$csvString += """"
		
		Return $csvString
	}

Function Lookup-vCenterGUID($hostName)
	{
		$hshHostnamesAndGUIDs = $null
		$hshHostnamesAndGUIDs = @{}
		
		$strClassID = $null
		$strClassID = "JPPacks.VMWare.vCenter.vCenterServer"
		
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
		If($arrObjHosts -eq $null)
			{
				$msg = "Unable to lookup objects of the class """ + $strClassID + """."
				Write-Out $msg 2
			}
		Else
			{
				$strGUID = $arrObjHosts.Id
			}
		Return $strGUID
	}


###MAIN LOOP###

#Load MOM Snap-Ins
If($fail -eq $false)
	{
		$blnLoaded = Load-MOMSnapin
		If($blnLoaded -ne $true)
			{$fail = $true}
	}

#Load vCenter Snap-Ins
If($fail -eq $false)
	{
		$blnLoaded = Load-VCSnapin
		If($blnLoaded -ne $true)
			{$fail = $true}
	}

#Connect to vCenter
If($fail -eq $false)
	{
		$wprefTmp = $warningPreference
		$warningPreference = "SilentlyContinue"
		
		#disconnect any zombie sessions
		If($objSC -eq $null)
			{}
		Else
			{Disconnect-VIServer $objSC -confirm:$false}
		#Disconnect-VIServer -force -confirm:$false
		
		$global:DefaultVIServers = $null
		$global:DefaultVIServer = $null
		
		#grab a new session
		$objSC = $null
		$objSC = Connect-VIServer $vCenterServer -User $viUsername -Password $viPassword -Notdefault
		$warningPreference = $wprefTmp
		If($objSC -eq $false -or $objSC -eq $null)
			{
				$msg = "Error connecting to the vcenter server """ + $vCenterServer + """ with username """ + $viUsername + """."
				Write-Out $msg 2
				$fail = $true
			}
		Else
			{
				$msg = "Connected to vcenter server """ + $vCenterServer + """ with username """ + $viUsername + """."
				Write-Out $msg
			}
	}

#Grab OpsMgr RMS Name
$opsmgrRMS = Get-RMSServer
If($opsmgrRMS -eq $null -or $opsmgrRMS -eq "")
	{
		$msg = "Could not get the RMS server name from the registry."
		Write-Out $msg
		$fail = $true
	}

#Connect to OpsMgr RMS
If($fail -eq $false)
	{
		$msg = "Connecting to the management server """ + $opsmgrRMS + """."
		Write-Out $msg
		$strConnect = New-ManagementGroupConnection $opsmgrRMS
		$msg = "Connection result: """ + $strConnect + """."
		Write-Out $msg
	}

#Do Work (grab stats, insert into PBag)
If($fail -eq $false)
	{
		$bag = $opsmgrAPI.CreatePropertyBag()
		
		#Lookup vCenter GUID
		$strVcGuid = Lookup-vCenterGUID $vCenterServer
		
		#grab events
		$dtDate = Get-Date
		$start = $dtDate.AddSeconds(($intervalSeconds * -1))
		$finish = $dtDate
		$events = $null
		$events = Get-VIEvent -server $objSC -start $start -finish $finish
		If($events -eq $null -or $events -eq "")
			{$blnContinue = $false}
		Else
			{$blnContinue = $true}
		
		If($blnContinue -eq $true)
			{
				$arrEvents = $null
				[array]$arrEvents = @()
				if($events -is [array])
					{$arrEvents = $events}
				Else
					{$arrEvents += $events}
				
				$i = 0
				$arrEvents | % {
					$objEvent = $_
					
					#$objEvent | out-host
					
					$pBagName = $i
					$pBagValue = $null
					[string]$pBagValue = Construct-CSVEventFromEvent $objEvent $vCenterName $strVcGuid
					$msg = "Name: " + $i + "`tString: " + $pBagValue
					write-out $msg
					$bag.AddValue($pBagName,$pBagValue)
					$i++
				}
				
				$bag
				$opsmgrAPI.Return($bag)
				$msg = "Collected " + $i + " events. Errors for run on host """ + $hostName + """: " + $Error
				Write-Out $msg
			}
		Else
			{
				$msg = "Collected 0 events. Errors for run on host """ + $hostName + """: " + $Error
				Write-Out $msg
			}
	}

If($error.count -ne 0)
	{
		$msg = "Errors for this run : """ + $Error + """."
		Write-Out $msg 2
	}

#Disconnect idle VI sessions
$sessMgr = Get-View ‘SessionManager’ -server $objSC
#added 4 hours to get-date below because all of my sessions seem to be 4 hours ahead when retrieved at through this code.
$sessMgr.SessionList | Where {($_.LastActiveTime).addminutes(5) -lt (Get-Date).AddHours(4)} | % {
		$strDomainShort = "CHEMISTRY"
		$strDomainUser = $strDomainShort + "\" + $viUsername
		[string]$strDomainUser = $strDomainUser.ToLower()
		$strSessionUsername = $_.Username
		[string]$strSessionUsername = $strSessionUsername.ToLower()
		#write-host -f green "$strSessionUsername, $strDomainUser"
		If($strSessionUsername -eq $strDomainUser)
			{$sessMgr.TerminateSession($_.Key)}
	}

#Disconnect from VI Server if necessary
If($objSC -eq $null -or $objSC -eq $false)
	{}
Else
	{Disconnect-VIServer $objSC -confirm:$false}

$msg = "Script ended."
Write-Out $msg