#Discover-Template.ps1

#TO CHANGE
##modify parent data
##hosting relationship class
##modify relationship
##edit arrProperties


Param($sourceID,$managedEntityID,$vCenterName,$dcName,$dcUID)
$fail = $false
$scriptName = "Discover-Template.ps1 b1"
$opsmgrAPI = New-Object -comObject 'MOM.ScriptAPI'

#parse args
$requiredArgs = $null
$requiredArgs = @()
$requiredArgs += "sourceID"
$requiredArgs += "managedEntityID"
$requiredArgs += "vCenterName"
$requiredArgs += "dcName"
$requiredArgs += "dcId"

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
		$OFS = ","
		[string]$strFailedArgs = $failedArgs
		$OFS = " "
		$failedArgs = $null
		$msg = "The following required arguments are missing: " + $strFailedArgs
		Write-Out $msg 2
		$fail = $true
	}
Else
	{
		Foreach($requiredArg in $requiredArgs)
			{
				$argValue = $null
				$argValue = (Get-Variable $requiredArg -eq silentlycontinue).Value
				$arrPairs = $requiredArg + " : " + $argValue
			}
		$OFS = " , "
		[string]$strArgPairs = $arrPairs
		$OFS = " "
		$msg = "The following args were passed: " + $strArgPairs
		Write-Out $msg
	}


#global vars
$script:debugLevel = 4										#verbosity
$script:blnWriteToScreen = $true					#write to the screen
$script:blnWriteToOpsMgrLog = $false			#write to the opsmgr log
$script:DiscoveryFilter = $dcName					#filter for the PowerCLI object command (whatever's used)


$gDiscoveredClassName = "JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster"



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
					{$opsmgrAPI.LogScriptEvent($scriptName,0,$severity,$msg)}
				Else{}
			}
	}

Function Load-Snapins
	{
		$fail = $null
		$fail = $false
		$snapin = "VMware.VimAutomation.Core"
		$msg = "Script is attempting to load snap-in: """ + $snapin + """."
		Write-Out $msg
		$snapinTest = $null
		$snapinTest = Get-PSSnapin $snapin -registered -ea "silentlycontinue"
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
		Connect-VIServer -server $vCenterName | out-null
		$warningPreference = $wprefTmp
		$objDC = $null
		$objDC = Get-Datacenter $dcName
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

Function Get-DiscoveryObjects($discoveryFilter)
	{
		$objVIObjects = $null
		$objVIObjects =  $dcName
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

#Prepare the hosting relationship class 
$objHostingClass = $null
$objHostingClass = $discoveryData.CreateClassInstance("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter']$")
If($objHostingClass -eq $null)
	{
		$msg = "Could not create a hosting class instance for the relationship discovery."
		Write-Out $msg 2
		$fail = $true
	}
Else
	{
		$objHostingClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter']/Uid$",$dcUID)
		$objHostingClass.AddProperty("$MPElement[Name='Windows!Microsoft.Windows.Computer']/PrincipalName$", $vCenterName)
		$msg = "An instance of the hosting class was created for the relationship discovery."
		Write-Out $msg
	}

#grab our vCenter objects
If($fail -eq $false)
	{
		$strFilter = $null
		$strFilter = $dcName
		$objVIObjects = Get-Cluster -location $strFilter
		If($objVIObjects -eq $null)
			{
				$msg = "No VI objects were found in this discovery with filter """ + $strFilter + """."
				Write-Out $msg 1
				$fail = $true
			}
	}

#parse our vCenter object properties
If($fail -eq $false)
	{
		If($objVIObjects -is [array])
			{$arrVIObjects = $objVIObjects}
		Else
			{
				$arrVIObjects = @()
				$arrVIObjects += $objVIObjects
			}
		
		$arrNames = $null
		$arrNames = @()
		Foreach($objVIObbject in $arrVIObjects)
			{
				#gather properties
				$arrProperties = @()
				$arrProperties += "Name"
				$arrProperties += "HAEnabled"
				$arrProperties += "HAFailoverLevel"
				$arrProperties += "DrsEnabled"
				$arrProperties += "DrsAutomationLevel"
				$arrProperties += "Id"
				$arrProperties += "Uid"
				
				#gather names for final message
				$vioName = $null
				$vioName = $objVIObbject.Name
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
				$objDiscoveredClass = $discoveryData.CreateClassInstance("$" + "MPElement[Name='" + $gDiscoveredClassName + "']$")
				If($objDiscoveredClass -eq $null)
					{
						$msg = "Could not create a class instance for this discovery."
						Write-Out $msg 2
						$fail = $true
						Break
					}
				
				#read properties from pshell object and add to discovery data
				Foreach($property in $arrPropertiesToDiscover)
					{
						$propValue = $null
						$propValue = $objVIObbject.$property
						If($propValue -ne $null)
							{
								$strAddProp = "$" + "MPElement[Name='" + $gDiscoveredClassName + "']/" + $property + "$"
								$objClass.AddProperty($strAddProp,$propValue)
							}
						Else
							{
								$msg = "Could not read value of the object's property """ + $property + """."
								Write-Out $msg 1
							}
					}
				
				#Add the parent's data to the class (not sure why this is required, but it is).
				$objDiscoveredClass.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$",$vioName)
				$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter']/Uid$",$dcUID)
				$objDiscoveredClass.AddProperty("$MPElement[Name='Windows!Microsoft.Windows.Computer']/PrincipalName$", $vCenterName)
				$discoveryData.AddInstance($objDiscoveredClass)
				
				#Add the Relationship
				$objRelationship = $null
				$objRelationship = $discoveryData.CreateRelationshipInstance("$MPElement[Name='JPPacks.VMWare.vCenter.Relationships.DatacenterHostsCluster']$")
				If($objRelationship -eq $null)
					{
						$msg = "Could not create the relationship class."
						Write-Out $msg 1
					}
				Else
					{
						$objRelationship.Source = $objHostingClass
						$objRelationship.Target = $objDiscoveredClass
						$discoveryData.AddInstance($objRelationship)
					}
			}
	}


		$intDiscoveryTotal = $arrNames.Count
		$OFS = ","; [string]$strNames = $arrNames; $OFS = " "
		$msg = "Script finished; discovered " + $intDiscoveryTotal + " clusters with names: """ + $strNames + """ located in the datacenter """ + $dcName + """. Returning the discovery data."
		Write-Out $msg
		#$opsmgrAPI.Return($discoveryData)
		$discoveryData
	}
	
	
	