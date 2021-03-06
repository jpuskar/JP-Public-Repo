#Discover-vCenterDatastores.ps1

##TODO
#create gHostingClassName


#TO CHANGE
##change $requiredArgs
##modify parent data
##modify attributes discovered
##modify discovery data class creation MPElement
##change scriptName
##change ending message

Param($sourceID,$managedEntityID,$vCenterName,$dcName,$dcUID)

$error.clear()
$fail = $false
$scriptName = "Discover-vCenterDatastores.ps1 b08 (auto) - "
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

#parse args
$requiredArgs = $null
$requiredArgs = @()
$requiredArgs += "sourceID"
$requiredArgs += "managedEntityID"
$requiredArgs += "vCenterName"
$requiredArgs += "dcName"
$requiredArgs += "dcUID"

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

Function Load-Snapins
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

Function Connect-ToVCenter
	{
		$fail = $null
		$fail = $false
		
		$wprefTmp = $warningPreference
		$warningPreference = "SilentlyContinue"
		$blnConnected = Connect-VIServer -server $vCenterName | out-null
		$warningPreference = $wprefTmp
		$objDC = $null
		$objDC = Get-Datacenter
		If($objDC -eq $null)
			{
				$fail = $true
				$msg = "Could not connect to the vcenter server: """ + $vCenterName + """."
				Write-Out $msg 2
			}
		Else
			{
				$msg = "Connected to the vcenter server: """ + $vCenterName + """."
				Write-Out $msg
			}
		
		If($fail -eq $false)
			{$retval = $true}
		Else
			{$retval = $false}
		Return $retval
	}

###MAIN LOOP###

#Load Snap-Ins
If($fail -eq $false)
	{
		$blnLoaded = Load-Snapins
		If($blnLoaded -ne $true)
			{$fail = $true}
	}

#Connect to vCenter
If($fail -eq $false)
	{
		$blnConnected = Connect-ToVCenter
		If($blnConnected -eq $false)
			{$fail = $true}
		Else
			{}
	}

#create the discovery data object
If($fail -eq $false)
	{
		#create the discovery data object
		$discoveryData = $null
		$discoveryData = $opsmgrAPI.CreateDiscoveryData(0,$sourceID,$managedEntityID)
		If($discoveryData -eq $null)
			{
				$msg = "Could not create Discovery Data."
				Write-Out $msg 2
				$fail = $true
			}
		Else
			{}
	}

#grab our vCenter objects
If($fail -eq $false)
	{
		$strFilter = $null
		$strFilter = $dcName
		$objVIObjects = $null
		$objVIObjects = Get-Datastore -datacenter $dcName
		If($objVIObjects -eq $null)
			{
				$msg = "No VI objects were found."
				Write-Out $msg 1
				$fail = $true
			}
	}

#parse our vCenter object properties
If($fail -eq $false)
	{
		$arrVIObjects = $null
		If($objVIObjects -is [array])
			{$arrVIObjects = $objVIObjects}
		Else
			{
				$arrVIObjects = @()
				$arrVIObjects += $objVIObjects
			}
		
		#Prepare the containment relationship source class
		$objSourceClass = $null
		$objSourceClass = $discoveryData.CreateClassInstance("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastores']$")
		$objSourceClass.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$","Datastores")
		$objSourceClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter']/Uid$",$dcUID)
		$objSourceClass.AddProperty("$MPElement[Name='Windows!Microsoft.Windows.Computer']/PrincipalName$", $vCenterName)
		
		$arrNames = $null
		$arrNames = @()
		Foreach($objVIO in $arrVIObjects)
			{
				#gather names for final message
				$vioName = $null
				$vioName = $objVIO.Name
				If($vioName -ne $null)
					{$arrNames += $vioName}
				Else
					{
						$msg = "Encountered a null VI Object; couldn't read an object's name."
						Write-Out $msg 2
						$fail = $true
						Break
					}
				
				#prepare the discovery class instance
				$objDiscoveredClass = $null
				$objDiscoveredClass = $discoveryData.CreateClassInstance("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastore']$")
				If($objDiscoveredClass -eq $null)
					{
						$msg = "Could not create a class instance for this discovery."
						Write-Out $msg 2
						$fail = $true
						Break
					}
				
				#Add the hosting parent's data to the class (required).
				
				
				#read properties from pshell object and add to discovery data
				$Name = $objVIO.Name
				$objDiscoveredClass.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$",$Name)
				$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastore']/Name$",$Name)
				$Id = $objVIO.Id
				$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastore']/Id$",$Id)
				$Uid = $objVIO.Uid
				$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastore']/Uid$",$Uid)
				$Accessible = $objVIO.Accessible
				$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastore']/Accessible$",$Accessible)
				$CapacityMB = $objVIO.CapacityMB
				$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastore']/CapacityMB$",$CapacityMB)
				$FreeSpaceMB = $objVIO.FreeSpaceMB
				$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastore']/FreeSpaceMB$",$FreeSpaceMB)
				$Type = $objVIO.Type
				$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastore']/Type$",$Type)
				$strDC = "datacenter"
				$dcName = $objVIO.$strDC
				$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastore']/Datacenter$",$dcName)
				$discoveryData.AddInstance($objDiscoveredClass)
				
				#Add the relationship
				$objRelationship = $null
				$objRelationship = $discoveryData.CreateRelationshipInstance("$MPElement[Name='JPPacks.VMWare.vCenter.Relationships.DatastoresContainsDatastore']$")
				If($objRelationship -eq $null)
					{
						$msg = "Could not create the relationship class."
						Write-Out $msg 2
					}
				Else
					{
						$objRelationship.Source = $objSourceClass
						$objRelationship.Target = $objDiscoveredClass
						$discoveryData.AddInstance($objRelationship)
					}
			}
	}

If($fail -eq $false)
	{
		$intDiscoveryTotal = $arrNames.Count
		$OFS = ","; [string]$strNames = $arrNames; $OFS = " "
		$msg = "Script finished; discovered " + $intDiscoveryTotal + " datastores with names: """ + $strNames + """ located in the server """ + $vCenterName + """. Returning the discovery data."
		Write-Out $msg
		
		$discoveryData
	}