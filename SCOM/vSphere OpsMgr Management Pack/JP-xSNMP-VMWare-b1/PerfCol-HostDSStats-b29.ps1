#PerfCol-HostDSStats.ps1

##TODO
#create gHostingClassName


#TO CHANGE
##change $requiredArgs
##modify parent data
##modify attributes discovered
##modify discovery data class creation MPElement
##change scriptName
##change ending message

Param($vCenterServer,$IntervalSeconds,$viUsername,$viPassword)
#$vCenterServer = $args[0]
#$hostName = $args[1]

$error.clear()
$fail = $false
$scriptName = "PerfCol-HostDSStats.ps1 b29 (auto)"
$opsmgrAPI = New-Object -comObject 'MOM.ScriptAPI'

#global vars
$script:debugLevel = 4									#verbosity
$script:blnWriteToScreen = $false				#write to the screen
$script:blnWriteToOpsMgrLog = $true			#write to the opsmgr log

$arrStatsToGrab = @()
$arrStatsToGrab += "disk.read.average"
$arrStatsToGrab += "disk.write.average"
$arrStatsToGrab += "disk.totalReadLatency.average"
$arrStatsToGrab += "disk.totalWriteLatency.average"
$arrStatsToGrab += "disk.numberRead.summation"
$arrStatsToGrab += "disk.numberWrite.summation"

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

Function Pull-DatastoreMOMObjects()
	{
		$hshHostnamesAndGUIDs = $null
		$hshHostnamesAndGUIDs = @{}
		
		$strClassID = $null
		$strClassID = "JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastore"
		
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
				$fail = $true
			}
		Else
			{$fail = $false}
		
		If($fail -eq $true)
			{$retval = $null}
		Else
			{$retval = $arrObjHosts}
		
		Return $retval
	}

Function Construct-CSVPropFromStat ($objStat,$hshDSName_ID_Map,$hshDSNamesGUIDs,$objHost)
	{
		#$objHost = $objHost
		[string]$DSName = $hshDSName_ID_Map.($objStat.Instance)
		$strUnit = $objStat.Unit
		$strCounterName = $objStat.MetricId + " from " + $objHost.Name
		$strCounterName = $strCounterName.ToLower()
		$strCounterName = $strCounterName + " (" + $strUnit + ")"
		$statValue = $objStat.Value
		$strGUID = $hshDSNamesGUIDs.Get_Item($DSName)
		
		#little bit of mapping
		[string]$customMonitoringObjectGUID = $strGUID
		[string]$strCounter = $strCounterName
		[string]$strObject = $DSName
		$dblValue = $statValue
		
		#sudo make me a sammich
		$csvString = $null
		$csvString = """"
		$csvString += $customMonitoringObjectGUID
		$csvString += ""","""
		$csvString += $strObject
		$csvString += ""","""
		$csvString += $strCounter
		$csvString += ""","""
		$csvString += $dblValue
		$csvString += """"
		
		Return $csvString
	}


Function Construct-CSVPropFromHash ($strType,$hshIOPS,$hshDSNamesIds,$hshDSNamesGUIDs)
	{
		$fail = $false
		$strUnit = $null
		$strCounterName = $null
		If($strType -eq "IOPS")
			{
				$strUnit = "number"
				$strCounterName = "Total Datastore IOPS for All Hosts"
				$strCounterName = $strCounterName + " (" + $strUnit + ")"
			}
		ElseIf($strType -eq "KBps")
			{
				$strUnit = "KBps"
				$strCounterName = "Total Datastore KBps IO for All Hosts"
				$strCounterName = $strCounterName + " (" + $strUnit + ")"
			}
		Else
			{$fail = $true}
		
		If($fail -eq $false)
			{
				$arrCSVStats = $null
				$arrCSVStats = @()
				$keys = $hshIOPS.Keys
				$keys | % {
					[string]$DSId = $_
					[string]$DSName = $hshDSNamesIds.($DSId)
					$statValue = $hshIOPS.$DSId
					$strGUID = $hshDSNamesGUIDs.$DSName
					#little bit of mapping
					[string]$customMonitoringObjectGUID = $strGUID
					[string]$strCounter = $strCounterName
					[string]$strObject = $DSName
					$dblValue = $statValue
					
					If($strGUID -ne "" -and $strGUID -ne $null)
						{
							#sudo make me a sammich
							$csvString = $null
							$csvString = """"
							$csvString += $customMonitoringObjectGUID
							$csvString += ""","""
							$csvString += $strObject
							$csvString += ""","""
							$csvString += $strCounter
							$csvString += ""","""
							$csvString += $dblValue
							$csvString += """"
							
							#write-host -f green "saving stat: $csvString"
							
							$arrCSVStats += $csvString
						}
				}
			}
		
		If($fail -eq $false)
			{$retval = $arrCSVStats}
		Else
			{$retval = $null}
		Return $retval
	}

Function Generate-DSLunNameMap($arrDatastores,$objHost,$objSC)
	{
		$hshMap = $null
		$hshMap = @{}
		
		$ds = Get-View (Get-View $objHost.ID -server $objSC).ConfigManager.StorageSystem -server $objSC
		$arrMounts = $ds.FileSystemVolumeInfo.MountInfo
		Foreach ($mount in $arrMounts)
			{
				$DSLunId = $null
				$DSName = $null
				$DSName = $mount.Volume.Name
				$extent = $mount.volume.extent
				If($extent -ne $null)
					{$DSLunID = $mount.volume.extent[0].diskname}
				Else {}
				If($DSLunId -ne $null -and $DSLunId -ne "")
					{$hshMap.Add($DSLunID,$DSName)}
			}
		
		Return $hshMap
	}

Function Generate-DSNameGUIDMap($arrDatastores,$objHost)
	{
		$hshMap = $null
		$hshMap = @{}
		
		$arrObjMOMobjects = Pull-DatastoreMOMObjects
		#$arrObjMOMobjects | out-host
		Foreach($DS in $arrDatastores)
			{
				$DSName = $DS.Name
				Foreach($objMOMObject in $arrObjMOMobjects)
					{
						$strMOMname = $objMOMObject.DisplayName
						If($strMOMname -eq $DSName)
							{
								[string]$strGUID = $objMomObject.Id
								$hshMap.Add($DSName,$strGUID)
							}
					}
			}
		
		Return $hshMap
	}

Function Update-DSTotalStats($arrStats,$hshDSNamesIds,$hshIOPS,$hshKBytes)
	{
		#write-host -f cyan "generating DS total stats"
		
		$arrDSIds = $hshDSNamesIds.Keys
		
		#Create and prep hshIOPS
		$arrDSIds | % {
			[string]$strId = $_
			If($hshIOPS.Keys -notcontains $_)
				{$hshIOPS.Add($_,0)}
		}
		
		#Create and prep hshKBytes
		$arrDSIds | % {
			[string]$strId = $_
			If($hshKBytes.Keys -notcontains $strId)
				{$hshKBytes.Add($strId,0)}
		}
		
		#create DS ID array
		$arrDSIDs = $null
		$arrDSIds = $hshDSNamesIds.Keys
		
		$arrStats | % {
			$objStat = $null
			$objStat = $_
			
			#Populate hshIOPS values
			$strStat = $null
			[string]$strStat = $objStat.MetricId
			If($strStat -eq "disk.numberRead.summation" -or $strStat -eq "disk.numberWrite.summation")
				{
					$dsInstance = $null
					[string]$dsInstance = $objStat.Instance
					$keys = $hshIOPS.Keys
					If($keys -contains $dsInstance)
						{
							$intStatVal = $null
							$intStatVal = $objStat.Value
							$iopsVal = $null
							$iopsVal = $hshIOPS.$dsInstance
							$newIopsVal = $null
							$newIopsVal = $iopsVal + $intStatVal
							$hshIOPS.$dsInstance = $newIopsVal
						}
				}
			
			#Populate hshKBytes values
			$strStat = $null
			[string]$strStat = $objStat.MetricId
			If($strStat -eq "disk.read.average" -or $strStat -eq "disk.write.average")
				{
					$dsInstance = $null
					[string]$dsInstance = $objStat.Instance
					$keys = $hshKBytes.Keys
					If($keys -contains $dsInstance)
						{
							$intStatVal = $null
							$intStatVal = $objStat.Value
							$KBytesVal = $null
							$KBytesVal = $hshKBytes.$dsInstance
							$newKBytesVal = $null
							$newKBytesVal = $KBytesVal + $intStatVal
							$hshKBytes.$dsInstance = $newKBytesVal
						}
				}
		}
		
		$arrHashtables = @()
		$arrHashtables += $hshIOPS
		$arrHashtables += $hshKBytes
		Return $arrHashtables
	}

###MAIN LOOP###

#Load MOM Snap-Ins
If($fail -eq $false)
	{
		$blnLoaded = Load-MOMSnapin
		If($blnLoaded -ne $true)
			{$fail = $true}
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

#Do Work (grab stats, insert into PBag)
If($fail -eq $false)
	{
		$intSeconds = 10
		[int]$maxSamples = $IntervalSeconds / $intSeconds
		$strStat = $script:strStatToCollect
		$bag = $opsmgrAPI.CreatePropertyBag()
		
		$hshIOPS = $null
		$hshKBytes = $null
		$hshIOPS = @{}
		$hshKBytes = @{}
		
		$i = 0
		$arrHosts = $null
		$arrHosts = Get-VMHost -server $objSC
		If($arrHosts -eq $null)
			{
				$msg = "Could not read hosts from vCenter Server."
				Write-Out $msg 2
				$fail = $true
			}
		
		If($fail -eq $false)
			{	
				$arrHosts | % {
					$objHost = $_
					
					$msg = "Collecting performance data for host: """ + $objHost.Name + """."
					Write-Out $msg
					
					#Generate a Name to SCSI ID map for this host
					$arrDatastores = $null
					$arrDatastores = Get-Datastore -VMHost $objHost -server $objSC
					
					#write-host -f yellow "`tGenerating DSLunNameMap"
					$hshDSNamesIds = $null
					$hshDSNamesIds = Generate-DSLunNameMap $arrDatastores $objHost $objSC
					
					#write-host -f yellow "`tGenerating DSNameGUIDMap"
					$hshDSNamesGUIDs = $null
					$hshDSNamesGUIDs = Generate-DSNameGUIDMap $arrDatastores $objHost
		
					#write-host -f yellow "`tGrabbing stats"
					#grab the stats
					$strHostname = $_.Name
					$arrStats = Get-Stat -entity $objHost -stat $arrStatsToGrab -intervalsecs $IntervalSeconds -maxsamples 1
					
					#process the stats into a pbag value, 'just throw it in the bag!
					$arrStats | % {
						$objStat = $_
						$pBagName = $i
						If($objStat.Value -ne $null -and $objStat.Value -ne "" -and ($hshDSNamesIds.ContainsKey($objStat.Instance)) -eq $true)
							{
								[string]$pBagValue = Construct-CSVPropFromStat $objStat $hshDSNamesIds $hshDSNamesGUIDs $objHost
								
		#						$msg = "Name: " + $i + "`tString: " + $pBagValue
		#						write-out $msg
								
								$bag.AddValue($pBagName,$pBagValue)
								$i++
							}
						Else
							{}
					}
					
					#process and update datastore total IOPS and RW stats.
					$arrDSHshStats = $null
					$arrDSHshStats = Update-DSTotalStats $arrStats $hshDSNamesIds $hshIOPS $hshKBytes
					$hshIOPS = $arrDSHshStats[0]
					$hshKBytes = $arrDSHshStats[1]
				}
		
				#Generate PBag Vales for total IOStats
				$arrIopsStats = $null
				$arrIopsStats = Construct-CSVPropFromHash "IOPS" $hshIOPS $hshDSNamesIds $hshDSNamesGUIDs
				$arrIopsStats | % {
					$strIopsStat = $_
					$pBagName = $i
					$pBagValue = $strIopsStat
					$bag.AddValue($pBagName,$pBagValue)
					$i++
				}
					
				#Generate PBag Vales for total KBytes
				$arrIopsStats = $null
				$arrIopsStats = Construct-CSVPropFromHash "KBps" $hshKBytes $hshDSNamesIds $hshDSNamesGUIDs
				$arrIopsStats | % {
					$strIopsStat = $_
					$pBagName = $i
					$pBagValue = $strIopsStat
					$bag.AddValue($pBagName,$pBagValue)
					$i++
				}
				
				
				$bag
				#$opsmgrAPI.Return($bag)
			}
	}

If($error.count -ne 0)
	{
		$msg = "Errors for this run : """ + $Error + """."
		Write-Out $msg 2
	}

#Disconnect idle VI sessions
$sessMgr = Get-View 'SessionManager' -server $objSC
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