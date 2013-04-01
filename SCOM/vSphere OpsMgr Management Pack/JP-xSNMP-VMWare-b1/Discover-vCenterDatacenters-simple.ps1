#Discover-vCenterDatacenters.ps1

##TODO
#create gHostingClassName


#TO CHANGE
##change $requiredArgs
##change $gDiscoveredClassName
##change $discoveryFilter
##change arrAttributes
##modify parent data
##hosting relationship class
##modify relationship
##edit arrProperties
##change scriptName
##change ending message

Param($sourceID,$managedEntityID,$vCenterName)

$error.clear()
$fail = $false
$scriptName = "Discover-vCenterDatcenters.ps1 b38 (simple;auto) " + $dcName

#$msg = "Starting script; loading MOM.ScriptAPI"
#Write-Out $msg

$opsmgrAPI = New-Object -comObject 'MOM.ScriptAPI'

#global vars
$script:debugLevel = 4										#verbosity
$script:blnWriteToScreen = $false					#write to the screen
$script:blnWriteToOpsMgrLog = $true #write to the opsmgr log
$script:DiscoveryFilter = $vCenterName		#filter for the PowerCLI object command (whatever's used)
#$gDiscoveredClassName = "JPPacks.VMWare.vCenter.vCenterServer.Datacenter"





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
		$arrPairs = $null
		$arrPairs = @()
		Foreach($requiredArg in $requiredArgs)
			{
				$argValue = $null
				$argValue = (Get-Variable $requiredArg -ea silentlycontinue).Value
				$arrPairs += $requiredArg + " : " + $argValue
			}
		$OFS = " , "
		[string]$strArgPairs = $arrPairs
		$OFS = " "
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

#Prepare the hosting relationship class
#$objHostingClass = $null
#$objHostingClass = $discoveryData.CreateClassInstance("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer']$")
#If($objHostingClass -eq $null)
#	{
#		$msg = "Could not create a hosting class instance for the relationship discovery."
#		Write-Out $msg 2
#		$fail = $true
#	}
#Else
#	{
#		$objHostingClass.AddProperty("$MPElement[Name='Windows!Microsoft.Windows.Computer']/PrincipalName$", $vCenterName)
#		$msg = "An instance of the hosting class was created for the relationship discovery."
#		Write-Out $msg
#	}

#grab our vCenter objects
If($fail -eq $false)
	{
		$strFilter = $null
		$strFilter = $dcName
		$objVIObjects = Get-Datacenter
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
		Foreach($objVIObject in $arrVIObjects)
			{
				#gather properties
				$arrProperties = @()
				$arrProperties += "Id"
				$arrProperties += "Name"
				$arrProperties += "Uid"
				
				#gather names for final message
				$vioName = $null
				$vioName = $objVIObject.Name
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
				$strDiscoveredClass = "$" + "MPElement[Name='" + $gDiscoveredClassName + "']$"
				$objDiscoveredClass = $null
				$objDiscoveredClass = $discoveryData.CreateClassInstance("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter']$")
				If($objDiscoveredClass -eq $null)
					{
						$msg = "Could not create a class instance for this discovery."
						Write-Out $msg 2
						$fail = $true
						Break
					}
				
				#read properties from pshell object and add to discovery data
				$arrPropValuePairs = $null
				$arrPropValuePairs = @()
				Foreach($property in $arrProperties)
					{
						$propValue = $null
						$propValue = $objVIObject.$property
						If($propValue -ne $null)
							{
								#$strAddProp = "$" + "MPElement[Name='" + $gDiscoveredClassName + "']/" + $property + "$"
								#$objDiscoveredClass.AddProperty($strAddProp,$propValue)
								$arrPropValuePairs += $property + " : " + $propValue
							}
						Else
							{
								$msg = "Could not read the value of the object's property """ + $property + """."
								Write-Out $msg 1
							}
					}
				
				$Uid = $objVIObject.Uid
				$Id = $objVIObject.Id
				$Name = $objVIObject.Name
				
				#Add the hosting parent's data to the class (required).
				$objDiscoveredClass.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$",$vioName)
				$objDiscoveredClass.AddProperty("$MPElement[Name='Windows!Microsoft.Windows.Computer']/PrincipalName$", $vCenterName)
				$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter']$",$Uid)
				$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter']$",$Id)
				$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter']$",$Name)
				$discoveryData.AddInstance($objDiscoveredClass)
				
				$OFS = " , "; [string]$strPropValuePairs = $arrPropValuePairs; $OFS = " "
				$msg = "Discovered an object with the following properties: " + $strPropValuePairs
				Write-Out $msg 1
				
				
				
#				#Add the Relationship
#				$objRelationship = $null
#				$objRelationship = $discoveryData.CreateRelationshipInstance("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterHostsDatacenter']$")
#				If($objRelationship -eq $null)
#					{
#						$msg = "Could not create the relationship class."
#						Write-Out $msg 1
#					}
#				Else
#					{
#						$objRelationship.Source = $objHostingClass
#						$objRelationship.Target = $objDiscoveredClass
#						$discoveryData.AddInstance($objRelationship)
#					}
			}
	}

If($fail -eq $false)
	{
		$intDiscoveryTotal = $arrNames.Count
		$OFS = ","; [string]$strNames = $arrNames; $OFS = " "
		$msg = "Script finished; discovered " + $intDiscoveryTotal + " datacenters with names: """ + $strNames + """ located in the server """ + $vCenterName + """. Returning the discovery data."
		Write-Out $msg
		
		#$opsmgrAPI.Return($discoveryData)
#		$msg = "Final discovery data: " + $ddata
#		Write-Out $msg
#		write-out -f cyan $ddata
#		$ddata | gm
		
		$discoveryData
	}