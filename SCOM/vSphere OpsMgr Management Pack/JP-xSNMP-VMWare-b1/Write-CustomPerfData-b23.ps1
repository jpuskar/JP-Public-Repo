#Write-CustomPerfData.ps1
#Write-Host "Running Script"
#use $args when testing manually, use $Param in opsmgr scripting\deployment
Param($xmlPerfData,$opsmgrUser,$opsmgrPass)
$error.clear()
$fail = $false
$scriptName = "Write-CustomPerfData.ps1 b28 (auto)"

$script:debugLevel = 4									#verbosity
$script:blnWriteToScreen = $false				#write to the screen
$script:blnWriteToOpsMgrLog = $true			#write to the opsmgr log

$opsmgrAPI = New-Object -comObject 'MOM.ScriptAPI'
If($xmlPerfData -is [xml])
	{$xmlData = $xmlPerfData}
Else
	{[xml]$xmlData = $xmlPerfData}

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
						$msg = "Error: Can't find the RMS Server name in registry."
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

Function Parse-XMLtoPerf($xmlData)
	{
		$strCounter = $null
		$strObject = $null
		$strValue = $null
		
		$prop = "#text"
		$arrObjProps = $null
		$arrObjProps = $xmlData.dataitem.property
		Foreach($objProp in $arrObjProps)
			{
				$name = $null
				[string]$name =  $objProp.Name
				$value = $null
				[string]$value = $objProp.$prop
				
				Switch($name)
					{
						"CustomMonitoredObjectGUID"
							{$strVIHostGUID = $value}
						"Counter"
							{$strCounter = $value}
						"Object"
							{$strObject = $value}
						"Value"
							{$strValue = $value}
					}
			}
		$objPerfData = New-Object Microsoft.EnterpriseManagement.Monitoring.CustomMonitoringPerformanceData($strObject,$strCounter,$strValue)
		
		Return $objPerfData
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
$msg = "Script starting; running as """ + $opsmgrUser + """."
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
		
		If($blnConnected -eq $false)
			{
				$msg = "Error, unable to connect to the RMS """ + $opsmgrRMS + """ with username """ + $opsmgrUser + """."
				Write-Out $msg 2
				$fail = $true
			}
		Else
			{
				$msg = "Connected to the Opsmgr RMS."
				Write-Out $msg
				$fail = $false
			}
		
	}

Function Pull-MO($GUID)
	{
		$retval = $null
		If($GUID -eq $null -or $GUID -eq "")
			{$retval = $nul}
		Else
			{$retval = Get-MonitoringObject $GUID -path "OperationsManagerMonitoring::"}
		
		Return $retval
	}

If($fail -eq $false)
	{
		#read the event data and output to the opsmgrlog
		$msg = "Parsing Event Data: "
		Write-Out $msg
		
		$strVIHostGUID = $null
		$prop = "#text"
		$arrObjProps = $null
		$arrObjProps = $xmlData.dataitem.property
		
		#grab properties from XML
		$prop = "#text"
		$arrObjProps = $null
		$arrObjProps = $xmlData.dataitem.property
		$intCount = $arrObjProps.Count
		$msg = "Processing " + $intCount + " performance data values."
		Write-Out $msg
		
		$arrPerfObjects = $null
		$arrPerfObjects = @()
		$i = 0
		Foreach($objProp in $arrObjProps)
			{
				$name = $null
				[string]$name =  $objProp.Name
				$value = $null
				[string]$value = $objProp.$prop
				$arrArgs = $value.Split(",")
				$strGUID = $arrArgs[0] -replace("""","")
				$strObject = $arrArgs[1] -replace("""","")
				$strCounter = $arrArgs[2] -replace("""","")
				$strValue = $arrArgs[3] -replace("""","")
				If($strValue -eq $null -or $strValue -eq "")
					{
						$msg = "Dropping performance data for object """ + $strGUID + """ with object name """ + $strObject + """ because the counter value is null."
						Write-Out $msg
					}
				Else
					{
						$objPerfData = $null
						$objPerfData = New-Object Microsoft.EnterpriseManagement.Monitoring.CustomMonitoringPerformanceData($strObject,$strCounter,$strValue)
						$msg = "Inserting performance data for OpsMgr Object number """ + $i + """ GUID: """ + $strGUID + """."
						Write-Out $msg
						$objVIHost = $null
						$objVIHost = Pull-MO $strGUID
						$objVIHost.InsertCustomMonitoringPerformanceData($objPerfData)
					}
				$i++
			}
		
		$msg = "Inserted " + $i + "Performance events. Errors: " + $Error
		Write-Out $msg
	}
