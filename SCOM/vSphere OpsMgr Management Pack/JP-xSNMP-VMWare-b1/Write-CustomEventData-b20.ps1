#Write-CustomEventData.ps1

#this script technically works now, but all the fields are off! Description and fullformattedmessage and key are going to need fixed also.
#the fields are off because .split isn't good enough.
Param($xmlEventData,$opsmgrUser,$opsmgrPass)
$error.clear()
$fail = $false
$scriptName = "Write-CustomEventData.ps1 b22 (auto)"

$script:debugLevel = 4									#verbosity
$script:blnWriteToScreen = $false				#write to the screen
$script:blnWriteToOpsMgrLog = $true			#write to the opsmgr log

$opsmgrAPI = New-Object -comObject 'MOM.ScriptAPI'
If($xmlEventData -is [xml])
	{$xmlData = $xmlEventData}
Else
	{[xml]$xmlData = $xmlEventData}

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

Function Build-XMLEventData ($objEventData,$arrHeaders)
	{
		$strXML = New-Object XML
		$rootElement = $strXML.CreateElement("DataItem")
		$strXML.AppendChild($rootElement) | out-null
		
		$arrHeaders | % {
			[string]$header = $_
			[string]$val = $objEventData.$header
			$objElement = $null
			$objElement = $strXML.CreateElement($header)
			$objElement.PSBase.InnerText = $val
			$rootElement.AppendChild($objElement) | out-null
		}
		
		Return $strXML
	}

Function Parse-EventDataToEvent($objEventData,$arrHeaders)
	{
		$publisherName = $objEventData.OM_PublisherName
		$eventNumber = $objEventData.OM_EventNumber
		$objEvent = New-Object Microsoft.EnterpriseManagement.Monitoring.CustomMonitoringEvent($publisherName,$eventNumber)
		
		$hshMap = @{}
		$hshMap.Add("OM_loggingComputer","loggingComputer")
		$hshMap.Add("OM_channel","channel")
		$hshMap.Add("OM_levelId","levelId")
		$hshMap.Add("OM_Message","message")
		$keys = $hshMap.Keys
		$keys | % {
			$key = $_
			$keyVal = $hshMap.$key
			$val = $objEventData.$key
			$objEvent.$keyVal = $val
		}
		
		$drop = $false
		If($objEventData.OM_Message -eq "" -or $objEventData.OM_Message -eq $null)
			{$drop = $true}
		
		If($drop -eq $false)
			{
				$eventData = $null
				$eventData = Build-XMLEventData $objEventData $arrHeaders
				[string]$strEventData = $eventData.innerXML
				$objEvent.EventData = $strEventData
				$retVal = $objEvent
			}
		Else
			{$retVal = $null}
		
		Return $retVal
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

If($xmlEventData -eq $null -or $opsmgrPass -eq $null -or $opsmgrUser -eq $null)
	{
		$msg = "Error, missing an argument."
		Write-Out $msg
		$fail = $true
	}

If($fail -eq $false)
	{
		$blnLoaded = Load-Snapins
		$opsmgrRMS = Get-RMSServer
	}

If($opsmgrRMS -eq $null -or $opsmgrRMS -eq "" -and $fail -eq $false)
	{
		$msg = "Could not get the RMS server name from the registry."
		Write-Out $msg
		$fail = $true
	}

If($fail -eq $false)
	{
		[string]$domain = ([adsi]'').dc
		$username = $domain + "\" + $opsmgrUser
		$username = $username -replace(" ","")
		
		$connections = $null
		$connections = Get-ManagementGroupConnection
		If($connections -eq $null -or $connections -eq "")
			{$blnConnected = $false}
		Else
			{$blnConnected = $true}
		
		If($blnConnected -eq $false)
			{
				$msg = "Connecting to the management server """ + $opsmgrRMS + """ as """ + $username + """."
				Write-Out $msg
				#ref: http://blogs.msdn.com/b/koteshb/archive/2010/02/13/powershell-creating-a-pscredential-object.aspx
				$secpasswd = ConvertTo-SecureString $opsmgrPass -AsPlainText -Force
				$mycreds = New-Object System.Management.Automation.PSCredential ($username, $secpasswd)
				$strConnect = New-ManagementGroupConnection $opsmgrRMS -Credential $mycreds
				$msg = "Connection result: """ + $strConnect + """."
				Write-Out $msg
				
				$connections = $null
				$connections = Get-ManagementGroupConnection
				If($connections -eq $null -or $connections -eq "")
					{$blnConnected = $false}
				Else
					{$blnConnected = $true}
			}
	}

If($fail -eq $false)
	{
		#read the event data and output to the opsmgrlog
		[string]$evtData = $xmlData.InnerXML
		$msg = "Original Event Data: " + $evtData
		Write-Out $msg
		
		$arrObjProps = $null
		$arrObjProps = $xmlData.dataitem.property
		If($arrObjProps -is [array])
			{}
		Else
			{
				$arrObjProps2 = @($arrObjProps)
				$arrObjProps = $arrObjProps2
				$arrObjProps2 = $null
			}
		
		$intCount = $arrObjProps.Count
		$msg = "Processing " + $intCount + " event data values."
		Write-Out $msg
		$prop = "#text"
		$arrObjProps | % {
			[string]$csvString = $_.$prop
			$arrHeaders = @("OM_customMonitoringObjectGUID","OM_Channel","OM_loggingComputer","OM_eventNumber","OM_levelId","OM_Message","OM_Username","OM_PublisherName","eventTypeId","severity","message","objectId","objectType","objectName","fault","key","chainId","createdTime","username","datacenter","computeResource","host","vm","ds","net","dvs","fullFormattedMessage","changeTag")
			$objEventData = ConvertFrom-CSV $csvString -header $arrHeaders
			
			$strGUID = $null
			[string]$strGUID = $objEventData.OM_CustomMonitoringObjectGuid
#			write-host -f yellow "strGUID: $strGUID"
			
			$objNewEvent = $null
			$objNewEvent = Parse-EventDataToEvent $objEventData $arrHeaders
			
#			$objEventData
#			$objNewEvent
#			exit
			
			If($objNewEvent -eq $null -or $objNewEvent -eq "" -or $strGUID -eq $null -or $strGUID -eq "")
				{
					$msg = "Dropping event data for object """ + $strGUID + """ because the event data is null."
					Write-Out $msg
				}
			Else
				{
#					$msg = "Inserting custom monitoring event for instance GUID """ + $strGUID + """."
#					Write-Out $msg
					$objVIHost = $null
					$objVIHost = Get-MonitoringObject $strGUID -path "OperationsManagerMonitoring::"
					$objVIHost.InsertCustomMonitoringEvent($objNewEvent)
				}
			$i++
			
		}
		
		
		$msg = "Errors: " + $Error
		Write-Out $msg
	}