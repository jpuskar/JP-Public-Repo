#Discover-vCenterHostVMInterfaces.ps1

##TODO
#create gHostingClassName


#TO CHANGE
##change $requiredArgs
##modify parent data
##modify attributes discovered
##modify discovery data class creation MPElement
##change scriptName
##change ending message

Param($sourceID,$managedEntityID,$vCenterName,$clusterName)

$error.clear()
$fail = $false
$scriptName = "Discover-vCenterHostVMInterfaces.ps1 b18 (auto) - "
$opsmgrAPI = New-Object -comObject 'MOM.ScriptAPI'

#global vars
$script:debugLevel = 4									#verbosity
$script:blnWriteToScreen = $true				#write to the screen
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
$requiredArgs += "clusterName"


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

Function Discover-VMNic($objVIO)
	{
		#prepare the discovery class instance
		$objDiscoveredClass = $null
		$objDiscoveredClass = $discoveryData.CreateClassInstance("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']$")
		If($objDiscoveredClass -eq $null)
			{
				$msg = "Could not create a class instance for this discovery."
				Write-Out $msg 2
				$fail = $true
				Break
			}
		
		#read properties from pshell object and add to discovery data
		#key properties of root element
		$Name = $objVIO.Name
		$objDiscoveredClass.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$",$Name)
				
		#UID of host (also a key property)
		[string]$VMHostUid = $objVIO.VMHostUid
		$arrPairs += ("VMHostUid" + ":" + $VMHostUid)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/VMHostUid$",$VMHostUid)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host']/Uid$",$VMHostUid)
		
		#other properties
		$BitRatePerSec = $objVIO.BitRatePerSec
		$arrPairs += ("BitRatePerSec" + ":" + $BitRatePerSec)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/BitRatePerSec$",$BitRatePerSec)
		
		$DeviceName = $objVIO.DeviceName
		$arrPairs += ("DeviceName" + ":" + $DeviceName)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/DeviceName$",$DeviceName)
		
		$DhcpEnabled = $objVIO.DhcpEnabled
		$arrPairs += ("DhcpEnabled" + ":" + $DhcpEnabled)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/DhcpEnabled$",$DhcpEnabled)
		
		$FullDuplex = $objVIO.FullDuplex
		$arrPairs += ("FullDuplex" + ":" + $FullDuplex)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/FullDuplex$",$FullDuplex)
		
		$Id = $objVIO.Id
		$arrPairs += ("Id" + ":" + $Id)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/Id$",$Id)
		
		$IP = $objVIO.IP
		$arrPairs += ("IP" + ":" + $IP)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/IP$",$IP)
		
		$Mac = $objVIO.Mac
		$arrPairs += ("Mac" + ":" + $Mac)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/Mac$",$Mac)
		
		$Name = $objVIO.Name
		$arrPairs += ("Name" + ":" + $Name)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/Name$",$Name)
		
		$SubnetMask = $objVIO.SubnetMask
		$arrPairs += ("SubnetMask" + ":" + $SubnetMask)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/SubnetMask$",$SubnetMask)
		
		[string]$VMHost = $objVIO.VMHost
		$arrPairs += ("VMHost" + ":" + $VMHost)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/VMHost$",$VMHost)
		
		$VMHostId = $objVIO.VMHostId
		$arrPairs += ("VMHostId" + ":" + $VMHostId)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/VMHostId$",$VMHostId)
		
		$WakeOnLanSupported = $objVIO.WakeOnLanSupported
		$arrPairs += ("WakeOnLanSupported" + ":" + $WakeOnLanSupported)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/WakeOnLanSupported$",$WakeOnLanSupported)
		
		$OFS = " , "; $strPairs = $arrPairs; $OFS = " "
		$msg = "Discovered a VMNic with the following properties: " + $strPairs
		Write-Out $msg
		
		Return $objDiscoveredClass
	}

Function Discover-VMK($objVIO)
	{
		#prepare the discovery class instance
		$objDiscoveredClass = $null
		$objDiscoveredClass = $discoveryData.CreateClassInstance("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']$")
		If($objDiscoveredClass -eq $null)
			{
				$msg = "Could not create a class instance for this discovery."
				Write-Out $msg 2
				$fail = $true
				Break
			}
		
		#key properties of root element
		$Name = $objVIO.Name
		$objDiscoveredClass.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$",$Name)
		
		#UID of host (also a key property)
		[string]$VMHostUid = $objVIO.VMHostUid
		$arrPairs += ("VMHostUid" + ":" + $VMHostUid)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/VMHostUid$",$VMHostUid)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host']/Uid$",$VMHostUid)
		
		#other properties
		$DeviceName = $objVIO.DeviceName
		$arrPairs += ("DeviceName" + ":" + $deviceName)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/DeviceName$",$DeviceName)
		
		$DhcpEnabled = $objVIO.DhcpEnabled
		$arrPairs += ("DhcpEnabled" + ":" + $DhcpEnabled)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/DhcpEnabled$",$DhcpEnabled)
		
		$Id = $objVIO.Id
		$arrPairs += ("Id" + ":" + $Id)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/Id$",$Id)
		
		$FaultToleranceLoggingEnabled = $objVIO.FaultToleranceLoggingEnabled
		$arrPairs += ("FaultToleranceLoggingEnabled" + ":" + $FaultToleranceLoggingEnabled)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/FaultToleranceLoggingEnabled$",$FaultToleranceLoggingEnabled)
		
		$IP = $objVIO.IP
		$arrPairs += ("IP" + ":" + $IP)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/IP$",$IP)
		
		$IPv6 = $objVIO.IPv6
		$arrPairs += ("IPv6" + ":" + $IPv6)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/IPv6$",$IPv6)
		
		$IPv6Enabled = $objVIO.IPv6Enabled
		$arrPairs += ("IPv6Enabled" + ":" + $IPv6Enabled)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/IPv6Enabled$",$IPv6Enabled)
		
		$IPv6ThroughDHCP = $objVIO.IPv6ThroughDHCP
		$arrPairs += ("IPv6ThroughDHCP" + ":" + $IPv6ThroughDHCP)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/IPv6ThroughDHCP$",$IPv6ThroughDHCP)
		
		$Mac = $objVIO.Mac
		$arrPairs += ("Mac" + ":" + $Mac)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/Mac$",$Mac)
		
		$ManagementTrafficEnabled = $objVIO.ManagementTrafficEnabled
		$arrPairs += ("ManagementTrafficEnabled" + ":" + $ManagementTrafficEnabled)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/ManagementTrafficEnabled$",$ManagementTrafficEnabled)
		
		$Mtu = $objVIO.Mtu
		$arrPairs += ("Mtu" + ":" + $Mtu)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/Mtu$",$Mtu)
		
		$Name = $objVIO.Name
		$arrPairs += ("Name" + ":" + $Name)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/Name$",$Name)
		
		$PortGroupName = $objVIO.PortGroupName
		$arrPairs += ("PortGroupName" + ":" + $PortGroupName)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/PortGroupName$",$PortGroupName)
		
		$SubnetMask = $objVIO.SubnetMask0
		$arrPairs += ("SubnetMask" + ":" + $SubnetMask)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/SubnetMask$",$SubnetMask)
		
		[string]$VMHost = $objVIO.VMHost
		$arrPairs += ("VMHost" + ":" + $VMHost)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/VMHost$",$VMHost)
		
		$VMHostId = $objVIO.VMHostId
		$arrPairs += ("VMHostId" + ":" + $VMHostId)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/VMHostId$",$VMHostId)
		
		$vMotionEnabled = $objVIO.vMotionEnabled
		$arrPairs += ("vMotionEnabled" + ":" + $vMotionEnabled)
		$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/vMotionEnabled$",$vMotionEnabled)
		
		$OFS = " , "; $strPairs = $arrPairs; $OFS = " "
		$msg = "Discovered a VMK with the following properties: " + $strPairs
		Write-Out $msg
		
		Return $objDiscoveredClass
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

#grab our vCenter hosts
If($fail -eq $false)
	{
		$objVIObjects = $null
		$objVIObjects = Get-VMHost -location $clusterName
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
		$intInterfaces = $null
		$intInterfaces = 0
		
		$arrVIObjects = $null
		If($objVIObjects -is [array])
			{$arrVIObjects = $objVIObjects}
		Else
			{
				$arrVIObjects = @()
				$arrVIObjects += $objVIObjects
			}
		
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
				
				$msg = "Discovering interfaces for host: """ + $vioName + """."
				Write-Out $msg
				$arrObjInterfaces = $null
				$arrObjInterfaces = Get-VMHostNetworkAdapter -vmhost $objVIO
				Foreach($objInterface in $arrObjInterfaces)
					{
						If($fail -eq $false)
							{
								$intInterfaces++
								#discover the object and add to the discoveryData
								$strIFName = $null
								$strIFName = $objInterface.Name
								$objDiscoveredClass = $null
								If($strIFName -like "vmnic*")
									{
										#DiscoverVMNics
										#$objDiscoveredClass = Discover-VMNic $objInterface
										#prepare the discovery class instance
										$objDiscoveredClass = $null
										$objDiscoveredClass = $discoveryData.CreateClassInstance("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']$")
										If($objDiscoveredClass -eq $null)
											{
												$msg = "Could not create a class instance for this discovery."
												Write-Out $msg 2
												$fail = $true
												Break
											}
										
										#read properties from pshell object and add to discovery data
										#key properties of root element
										$name = $null
										$Name = $objInterface.Name
										$objDiscoveredClass.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$",$Name)
											
										#UID of host (also a key property)
										$VMHostUid = $null
										[string]$VMHostUid = $objInterface.VMHostUid
										$arrPairs = $null
										$arrPairs = @()
										$arrPairs += ("VMHostUid" + ":" + $VMHostUid)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/VMHostUid$",$VMHostUid)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host']/Uid$",$VMHostUid)
										
										#other properties
										$BitRatePerSec = $objInterface.BitRatePerSec
										$arrPairs += ("BitRatePerSec" + ":" + $BitRatePerSec)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/BitRatePerSec$",$BitRatePerSec)
										
										$DeviceName = $objInterface.DeviceName
										$arrPairs += ("DeviceName" + ":" + $DeviceName)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/DeviceName$",$DeviceName)
										
										$DhcpEnabled = $objInterface.DhcpEnabled
										$arrPairs += ("DhcpEnabled" + ":" + $DhcpEnabled)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/DhcpEnabled$",$DhcpEnabled)
										
										$FullDuplex = $objInterface.FullDuplex
										$arrPairs += ("FullDuplex" + ":" + $FullDuplex)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/FullDuplex$",$FullDuplex)
										
										$Id = $objInterface.Id
										$arrPairs += ("Id" + ":" + $Id)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/Id$",$Id)
										
										$IP = $objInterface.IP
										$arrPairs += ("IP" + ":" + $IP)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/IP$",$IP)
										
										$Mac = $objInterface.Mac
										$arrPairs += ("Mac" + ":" + $Mac)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/Mac$",$Mac)
										
										$Name = $objInterface.Name
										$arrPairs += ("Name" + ":" + $Name)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/Name$",$Name)
										
										$SubnetMask = $objInterface.SubnetMask
										$arrPairs += ("SubnetMask" + ":" + $SubnetMask)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/SubnetMask$",$SubnetMask)
										
										[string]$VMHost = $objInterface.VMHost
										$arrPairs += ("VMHost" + ":" + $VMHost)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/VMHost$",$VMHost)
										
										$VMHostId = $objInterface.VMHostId
										$arrPairs += ("VMHostId" + ":" + $VMHostId)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/VMHostId$",$VMHostId)
										
										$WakeOnLanSupported = $objInterface.WakeOnLanSupported
										$arrPairs += ("WakeOnLanSupported" + ":" + $WakeOnLanSupported)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/WakeOnLanSupported$",$WakeOnLanSupported)
										
										$OFS = " , "; $strPairs = $arrPairs; $OFS = " "
										$msg = "Discovered a VMNic with the following properties: " + $strPairs
										Write-Out $msg
									}
								ElseIf($strIFName -like "vmk*")
									{
										#DiscoverVMKs
										#$objDiscoveredClass = Discover-VMK $objInterface
										#prepare the discovery class instance
										$objDiscoveredClass = $null
										$objDiscoveredClass = $discoveryData.CreateClassInstance("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']$")
										If($objDiscoveredClass -eq $null)
											{
												$msg = "Could not create a class instance for this discovery."
												Write-Out $msg 2
												$fail = $true
												Break
											}
										
										#key properties of root element
										$name = $null
										[string]$Name = $objInterface.Name
										$objDiscoveredClass.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$",$Name)
										
										#UID of host (also a key property)
										$VMHostUid = $null
										[string]$VMHostUid = $objInterface.VMHostUid
										$arrPairs = $null
										$arrPairs = @()
										$arrPairs += ("VMHostUid" + ":" + $VMHostUid)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMNic']/VMHostUid$",$VMHostUid)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host']/Uid$",$VMHostUid)
										
										#other properties
										$DeviceName = $objInterface.DeviceName
										$arrPairs += ("DeviceName" + ":" + $deviceName)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/DeviceName$",$DeviceName)
										
										$DhcpEnabled = $objInterface.DhcpEnabled
										$arrPairs += ("DhcpEnabled" + ":" + $DhcpEnabled)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/DhcpEnabled$",$DhcpEnabled)
										
										$Id = $objInterface.Id
										$arrPairs += ("Id" + ":" + $Id)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/Id$",$Id)
										
										$FaultToleranceLoggingEnabled = $objInterface.FaultToleranceLoggingEnabled
										$arrPairs += ("FaultToleranceLoggingEnabled" + ":" + $FaultToleranceLoggingEnabled)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/FaultToleranceLoggingEnabled$",$FaultToleranceLoggingEnabled)
										
										$IP = $objInterface.IP
										$arrPairs += ("IP" + ":" + $IP)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/IP$",$IP)
										
										$IPv6 = $objInterface.IPv6
										$arrPairs += ("IPv6" + ":" + $IPv6)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/IPv6$",$IPv6)
										
										$IPv6Enabled = $objInterface.IPv6Enabled
										$arrPairs += ("IPv6Enabled" + ":" + $IPv6Enabled)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/IPv6Enabled$",$IPv6Enabled)
										
										$IPv6ThroughDHCP = $objInterface.IPv6ThroughDHCP
										$arrPairs += ("IPv6ThroughDHCP" + ":" + $IPv6ThroughDHCP)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/IPv6ThroughDHCP$",$IPv6ThroughDHCP)
										
										$Mac = $objInterface.Mac
										$arrPairs += ("Mac" + ":" + $Mac)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/Mac$",$Mac)
										
										$ManagementTrafficEnabled = $objInterface.ManagementTrafficEnabled
										$arrPairs += ("ManagementTrafficEnabled" + ":" + $ManagementTrafficEnabled)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/ManagementTrafficEnabled$",$ManagementTrafficEnabled)
										
										$Mtu = $objInterface.Mtu
										$arrPairs += ("Mtu" + ":" + $Mtu)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/Mtu$",$Mtu)
										
										$Name = $objInterface.Name
										$arrPairs += ("Name" + ":" + $Name)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/Name$",$Name)
										
										$PortGroupName = $objInterface.PortGroupName
										$arrPairs += ("PortGroupName" + ":" + $PortGroupName)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/PortGroupName$",$PortGroupName)
										
										$SubnetMask = $objInterface.SubnetMask0
										$arrPairs += ("SubnetMask" + ":" + $SubnetMask)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/SubnetMask$",$SubnetMask)
										
										[string]$VMHost = $objInterface.VMHost
										$arrPairs += ("VMHost" + ":" + $VMHost)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/VMHost$",$VMHost)
										
										$VMHostId = $objInterface.VMHostId
										$arrPairs += ("VMHostId" + ":" + $VMHostId)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/VMHostId$",$VMHostId)
										
										$vMotionEnabled = $objInterface.vMotionEnabled
										$arrPairs += ("vMotionEnabled" + ":" + $vMotionEnabled)
										$objDiscoveredClass.AddProperty("$MPElement[Name='JPPacks.VMWare.vCenter.vCenterServer.Datacenter.ESXCluster.Host.VMKernel']/vMotionEnabled$",$vMotionEnabled)
										
										$OFS = " , "; $strPairs = $arrPairs; $OFS = " "
										$msg = "Discovered a VMK with the following properties: " + $strPairs
										Write-Out $msg
									}
								$discoveryData.AddInstance($objDiscoveredClass)
							}
					}
			}
	}

If($fail -eq $false)
	{
		$intDiscoveryTotal = $arrNames.Count
		$OFS = ","; [string]$strNames = $arrNames; $OFS = " "
		$msg = "Script finished; discovered """ + $intInterfaces + """ interface(s) for" + $intDiscoveryTotal + " hosts with names: """ + $strNames + """ located in the server """ + $vCenterName + """. Returning the discovery data."
		Write-Out $msg
		$msg = "Errors: " + $error
		Write-Out $msg
		$discoveryData
	}