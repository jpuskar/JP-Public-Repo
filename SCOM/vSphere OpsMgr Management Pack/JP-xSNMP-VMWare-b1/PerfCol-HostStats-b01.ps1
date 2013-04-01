#PerfCol-HostStats.ps1

#TO CHANGE
##change $requiredArgs
##modify parent data
##modify attributes discovered
##modify discovery data class creation MPElement
##change scriptName
##change ending message

Param($vCenterServer,$IntervalSeconds,$viUsername,$viPassword)

$error.clear()
$fail = $false
$scriptName = "PerfCol-HostStats.ps1 b03 (auto)"
$opsmgrAPI = New-Object -comObject 'MOM.ScriptAPI'

#global vars
$script:debugLevel = 4									#verbosity
$script:blnWriteToScreen = $false				#write to the screen
$script:blnWriteToOpsMgrLog = $true			#write to the opsmgr log

#$arrStatsToGrab += ""
$arrStatsToGrab = @()
#CPU
$arrStatsToGrab += "cpu.usage.average"
#$arrStatsToGrab += "cpu.usage.maximum"
#$arrStatsToGrab += "cpu.swapwait.summation"
#$arrStatsToGrab += "cpu.wait.summation"
#Memory
$arrStatsToGrab += "mem.usage.average"
#$arrStatsToGrab += "mem.usage.maximum"
#Network -- note, this doesn't work unless the entity is a vminterface.
#$arrStatsToGrab += "net.usage.average"
#$arrStatsToGrab += "net.droppedrx.summation"
#$arrStatsToGrab += "net.droppedtx.summation"
#Disk
$arrStatsToGrab += "disk.usage.average"
$arrStatsToGrab += "disk.read.average"
$arrStatsToGrab += "disk.write.average"
$arrStatsToGrab += "disk.totalReadLatency.average"
$arrStatsToGrab += "disk.totalWriteLatency.average"
$arrStatsToGrab += "disk.commands.summation"
$arrStatsToGrab += "disk.commandsaborted.summation"
$arrStatsToGrab += "disk.busresets.summation"

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

Function Connect-ToVCenter($user,$pass)
	{
		$fail = $null
		$fail = $false
		
		#it sometimes complains about these variables getting set, probably by other scripts.
		#$global:DefaultVIServers = $null
		#$global:DefaultVIServer = $null
		
		If($defaultVIServer -eq $null)
			{$blnConnected = $false}
		Else
			{$blnConnected = $true}
		
		If($blnConnected -eq $false)
			{
				$wprefTmp = $warningPreference
				$warningPreference = "SilentlyContinue"
				#$blnConnected = Connect-VIServer -server $vCenterServer -User $user -Password $pass| out-null
				$blnConnected = Connect-VIServer -server $vCenterServer -User $user -Password $pass| out-null
				$warningPreference = $wprefTmp
				$objDC = $null
				$objDC = Get-Datacenter
				If($objDC -eq $null)
					{
						$fail = $true
						$msg = "Could not connect to the vcenter server: """ + $vCenterServer + """."
						Write-Out $msg 2
					}
				Else
					{
						$msg = "Connected to the vcenter server: """ + $vCenterServer + """."
						Write-Out $msg
					}
			}
		
		If($fail -eq $false)
			{$retval = $true}
		Else
			{$retval = $false}
		Return $retval
	}

Function Pull-MOMObjectsByClass($strClassId)
	{
		$hshHostnamesAndGUIDs = $null
		$hshHostnamesAndGUIDs = @{}
		
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

Function Construct-CSVPropFromDSStat ($objStat,$hshDSName_ID_Map,$hshDSNamesGUIDs,$objHost)
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

Function Construct-CSVPropFromDSStat_ForHost ($objStat,$hshDSName_ID_Map,$hshDSNamesGUIDs,$objHost,$strHostGUID)
	{
		#$objHost = $objHost
		#$strGUID = $strGUID
		[string]$DSName = $hshDSName_ID_Map.($objStat.Instance)
		$strUnit = $objStat.Unit
		$strCounterName = $objStat.MetricId + " for " + $DSName
		#$strCounterName = $strCounterName.ToLower()
		$strCounterName = $strCounterName + " (" + $strUnit + ")"
		$statValue = $objStat.Value
		
		#little bit of mapping
		[string]$customMonitoringObjectGUID = $strHostGUID
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

Function Construct-CSVPropFromStat ($objStat,$strGuid,$strHostname)
	{
		#$strGUID = $strGuid
		$strInstanceName = $null
		[string]$strInstanceName = $objStat.Instance
		If($strInstanceName -eq $null -or $strInstanceName -eq "")
			{$strInstanceName = $strHostname}
		$strUnit = $objStat.Unit
		$strCounterName = $objStat.MetricId
		$strCounterName = $strCounterName.ToLower()
		$strCounterName = $strCounterName + " (" + $strUnit + ")"
		$statValue = $objStat.Value
		
		#little bit of mapping
		[string]$customMonitoringObjectGUID = $strGUID
		[string]$strCounter = $strCounterName
		[string]$strObject = $strInstanceName
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

Function Generate-DSLunNameMap($arrDatastores,$objHost)
	{
		$hshMap = $null
		$hshMap = @{}
		
		$ds = Get-View (Get-View $objHost.ID).ConfigManager.StorageSystem
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
		
		$strClassId = $null
		$strClassId = "JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastore"
		$arrObjMOMobjects = Pull-MOMObjectsByClass $strClassId
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

Function Lookup-HostGUID($hostName)
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
						If($strHostname -eq $hostName)
							{$strGUID = $objHost.Id}
					}
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
		$blnConnected = Connect-ToVCenter $viUsername $viPassword
		If($blnConnected -eq $false)
			{$fail = $true}
		Else
			{}
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
		
		$i = 0
		$arrHosts = Get-VMHost
		$arrHosts | % {
			$objHost = $_
			
			$msg = "Collecting performance data for host: """ + $objHost.Name + """."
			Write-Out $msg
			
			##Prep regular stat information
			$objHostName = $null
			[string]$objHostName = $objHost.Name
			
			$strHostGUID = $null
			[string]$strHostGUID = Lookup-HostGUID $objHostName
			
			##Prep datastore stat information
			#Generate a Name to SCSI ID map for this host
			$arrDatastores = $null
			$arrDatastores = Get-Datastore -VMHost $objHost
			#write-host -f yellow "`tGenerating DSLunNameMap"
			$hshDSNamesIds = $null
			$hshDSNamesIds = Generate-DSLunNameMap $arrDatastores $objHost
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
				If($objStat.Value -eq $null -or $objStat.Value -eq "")
					{}
				ElseIf(($hshDSNamesIds.ContainsKey($objStat.Instance)) -eq $true)
					{
						$pBagName = $i
						#insert perf data for datastore object
						$pBagValue = $null
						[string]$pBagValue = Construct-CSVPropFromDSStat $objStat $hshDSNamesIds $hshDSNamesGUIDs $objHost
#						$msg = "Name: " + $i + "`tString: " + $pBagValue
#						write-out $msg
						$bag.AddValue($pBagName,$pBagValue)
						$i++
						
						$pBagName = $i
						$pBagValue = $null
						#insert perf data for host object
						[string]$pBagValue = Construct-CSVPropFromDSStat_ForHost $objStat $hshDSNamesIds $hshDSNamesGUIDs $objHost $strHostGUID
#						$msg = "Name: " + $i + "`tString: " + $pBagValue
#						write-out $msg
						$bag.AddValue($pBagName,$pBagValue)
						$i++
					}
				Else
					{
						$pBagName = $i
						$blnDropStat = $false
						#special cases
						[string]$strStatName = $objStat.MetricId
						If($strStatName -eq "cpu.usage.average")
							{
								#drop cpu % stats for individual cores, keep for overall
								If($objStat.Instance -ne "")
									{$blnDropStat = $true}
								Else
									{$blnDropStat = $false}
							}
						
						ElseIf($strStatName -like "disk*")
							{
								#drop disk stats for disks that aren't shared between all hosts
								$blnDropStat = $true
							}
						
						If($blnDropStat -eq $false)
							{
								#insert perf data for host
								[string]$pBagValue = Construct-CSVPropFromStat $objStat $strHostGUID $objHostname
								$msg = "Name: " + $i + "`tString: " + $pBagValue
								write-out $msg
								$bag.AddValue($pBagName,$pBagValue)
								$i++
							}
					}
			}
		}
		
		$bag
		#$opsmgrAPI.Return($bag)
		$msg = "Collected " + $i + " stats. Errors for run on host """ + $hostName + """: " + $Error
		Write-Out $msg
	}

