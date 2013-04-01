# ESXi-Install-Script
# johnpuskar@gmail.com
# 02/02/2013

#PowerCLI
# Download -
# http://communities.vmware.com/community/vmtn/server/vsphere/automationtools/powercli
# Referece -
# http://pubs.vmware.com/vsphere-51/topic/com.vmware.vsphere.scripting.doc/GUID-7F7C5D15-9599-4423-821D-7B1FE87B3A96.html

#vSphere CLI (for snmp)
# Download -
# https://my.vmware.com/web/vmware/details?downloadGroup=VSP510-VCLI-510&productId=285

#VDSPowerCLI (no longer used)
# cmdlets download - http://labs.vmware.com/flings/vdspowercli
# http://blogs.vmware.com/vipowershell/2011/11/vsphere-distributed-switch-powercli-cmdlets.html
# not compatible with powercli 5.1!

#== Getting Started! ==

#== Variables ==
# Generic
$vCenterServer = "vcenter.domain.com"
$vmHostName = "vm1.domain.com"
$vSwitchName = "SAN-Switch"
$ntpHostname = "ntp.domain.com"
$snmpTrapReceiver = "opsmgr.domain.com"
$snmpTrapCommunity = "public"
$omsaPath = "/vmfs/volumes/san-esx0-lun0/VIBs/OM-SrvAdmin-Dell-Web-7.1.0-5304.VIB-ESX50i_A00/metadata.zip"
# Port Groups
$arrPGsToCreate = @()
$arrPGsToCreate += New-Object –TypeName PSObject –Prop (@{"Name" = "100_san1";"VLAN" = "100"})
$arrPGsToCreate += New-Object –TypeName PSObject –Prop (@{"Name" = "200_san2";"VLAN" = "200"})
$arrPGsToCreate += New-Object –TypeName PSObject –Prop (@{"Name" = "100_san1-vmk1";"VLAN" = "100"})
$arrPGsToCreate += New-Object –TypeName PSObject –Prop (@{"Name" = "200_san2-vmk1";"VLAN" = "200"})
$arrPGsToCreate += New-Object –TypeName PSObject –Prop (@{"Name" = "100_san1-vmk2";"VLAN" = "100"})
$arrPGsToCreate += New-Object –TypeName PSObject –Prop (@{"Name" = "200_san2-vmk2";"VLAN" = "200"}) 
$arrPGsToCreate += New-Object –TypeName PSObject –Prop (@{"Name" = "300_nfs";"VLAN" = "300"})
$arrPGsToCreate += New-Object –TypeName PSObject –Prop (@{"Name" = "400_vmotion";"VLAN" = "400"})
$arrPGsToCreate += New-Object –TypeName PSObject –Prop (@{"Name" = "401_ft";"VLAN" = "401"})
# VMKernels
$arrVMKsToCreate = @()
$arrVMKsToCreate += New-Object –TypeName PSObject –Prop (@{"PGName" = "100_san1-vmk1";"IP" = "x.x.x.x";"subnet" = "255.255.255.0"})
$arrVMKsToCreate += New-Object –TypeName PSObject –Prop (@{"PGName" = "200_san2-vmk1";"IP" = "x.x.x.x";"subnet" = "255.255.255.0"})
$arrVMKsToCreate += New-Object –TypeName PSObject –Prop (@{"PGName" = "300_pan";"IP" = "x.x.x.x";"subnet" = "255.255.255.0"})
$arrVMKsToCreate += New-Object –TypeName PSObject –Prop (@{"PGName" = "400_vmotion";"IP" = "x.xx.x";"subnet" = "255.255.255.0"})
$arrVMKsToCreate += New-Object –TypeName PSObject –Prop (@{"PGName" = "401_ft";"IP" = "x.x.x.x";"subnet" = "255.255.255.0"})
# iSCSI Targets
$arrIScsiTargetsInfo = @()
$arrIScsiTargetsInfo += New-Object –TypeName PSObject –Prop (@{"Address" = "x.x.x.x";"Type" = "send"})
$arrIScsiTargetsInfo += New-Object –TypeName PSObject –Prop (@{"Address" = "x.x.x.x";"Type" = "send"})
$arrIScsiTargetsInfo += New-Object –TypeName PSObject –Prop (@{"Address" = "x.x.x.x";"Type" = "send"})
$arrIScsiTargetsInfo += New-Object –TypeName PSObject –Prop (@{"Address" = "x.x.x.x";"Type" = "send"})
#NFS Targets
$arrNfsDatastores = @()
$arrNfsDatastores += New-Object -TypeName PSObject -Prop (@{"Name" = "vdr-backups"; "Path" = "/mnt/dataon1/vdrbackups/vdrbackups/"; "Host" = "10.146.232.113"})


#==== Do the Work ====
#Get the host password (for SNMP)
$rootPass = Read-Host -Prompt "Enter host root password" -AsSecureString

#Connect to vCenter Server
$VCUserCredentials = Get-Credential
Connect-VIServer -Server vCenterServer -Protocol "https" -Credential $VCUserCredentials

$vmHost = Get-VMHost -Name $vmHostName
$oCLI = Get-ESXCli -vmhost $vmHost

#Put the host in maintenance mode
Set-VMHost -VMhost $vmHost -State "Maintenance"

#Create the SAN virtual switch
$vs = New-VirtualSwitch -VMHost $vmHost -Name $vSwitchName

#Create the Port Groups
$arrPGsToCreate | % {New-VirtualPortGroup -VirtualSwitch $vs -Name $_.Name -VLanId $_.VLAN}

#Create SAN, vMotion, FT, and NFS vmkernels
$arrVMKsToCreate | % {New-VMHostNetworkAdapter -VMHost $vmHost -PortGroup $_.PGName -VirtualSwitch $vs -IP $_.IP -SubnetMask $_.subnet}

#Enable SSH
$vmHost | Get-VMHostService | where {$_.Key -eq "TSM-SSH"} | Set-VMHostService -Policy "On"
$vmHost | Get-VMHostFirewallException | where {$_.Name -eq "SSH Server"} | Set-VMHostFirewallException -Enabled:$true
$vmHost | Get-VMHostService | where {$_.Key -eq "TSM-SSH"} | Start-VMHostService

#Enable ESXi Service Console
$vmHost | Get-VMHostService | where {$_.Key -eq "TSM"} | Set-VMHostService -Policy "On"
$vmHost | Get-VMHostService | where {$_.Key -eq "TSM"} | Start-VMHostService

#Disable SSH Warnings
Set-VmHostAdvancedConfiguration -vmhost $vmhost -Name UserVars.SuppressShellWarning -Value ( [system.int32] 1 )

#Set NTP Server and Enable
Add-VmHostNtpServer -NtpServer $ntpHostname -VMHost $vmHost
$vmHost | Get-VMHostService | where {$_.Key -eq "ntpd"} | Set-VMHostService -Policy "On"
$vmHost | Get-VMHostFirewallException | where {$_.Name -eq "NTP client"} | Set-VMHostFirewallException -Enabled:$true
$vmHost | Get-VMHostService | where {$_.Key -eq "ntpd"} | Start-VMHostService

# Enable software iSCSI HBA
$oCLI.iscsi.software.set($true)
Sleep -s 10

# Add iSCSI Targets
$IScsiHba = Get-VMHostHba -vmhost $vmHost -Type "iscsi"
$arrIScsiTargetsInfo | % {$IScsiHba | New-IScsiHbaTarget -Address $_.Address -type $_.Type}

#Add NFS Datastore
$nfsDatastores | % {New-Datastore -Nfs -VMHost $vmHost -Name $_.Name -Path $_.Path -NfsHost $_.Host}

#Install Dell OMSA
Install-VMHostPatch -vmhost $vmHost -HostPath $omsaPath

#Configure SNMP
$expression = "perl ""C:\Program Files (x86)\VMware\VMware vSphere CLI\bin\vicfg-snmp.pl"" --server " + $vmHost.Name + " --username root --password " + $rootPass + " -t " + $snmpTrapReceiver + "@162/" + $snmpTrapCommunity
Invoke-Expression $expression
$expression = "perl ""C:\Program Files (x86)\VMware\VMware vSphere CLI\bin\vicfg-snmp.pl"" --server " + $vmHost.Name + " --username root --password " + $rootPass + " --enable"
Invoke-Expression $expression
$expression = "perl ""C:\Program Files (x86)\VMware\VMware vSphere CLI\bin\vicfg-snmp.pl"" --server " + $vmHost.Name + " --username root --password " + $rootPass + " --test"
Invoke-Expression $expression

#warn user of manual steps needed next
$msgs = @()
$msgs += "MANUAL STEPS REQUIRED:"
$msgs += " * Add vmnics to the vSwitches and Port Groups, and then test with vmkping."
$msgs += " * Bind vmk's to software iSCSI HBA."
$msgs += " * Give host's initiator access to LUNs on necessary iSCSI targets."
$msgs += " * Add host to VDS and configure dvUplinks"
$msgs += " * Migrate appropriate vmkernels to the VDS"
$msgs += " * Assign FT to the ft vmkernel"
$msgs += " * Assign mgmt traffic to PAN vmkernel"
$msgs += " * Assign vmotion to vmotion vmkernel"
$msgs | % {write-host -f yellow $_}

$go = $false
While ($go -eq $false)
	{$text = Read-Host "Type 'continue' when the steps are complete."; If($text -eq "continue"){$go = $true}}

# Configure round-robin multipathing policy on all iscsi paths
$oCLI.storage.nmp.path.list() | group-Object –Property Device | Where {$_.Name –like "naa*"} | %{$oCLI.storage.nmp.device.set($null, $_.Name, "VMW_PSP_RR")}

#Reboot host
Restart-VMHost -vmhost $vmHost -confirm:$false
	
#Exit maintenance mode
Set-VMHost -VMhost $vmHost -State "Connected"

# MANUAL STEP
# Attach update baselines
# Scan for updates
# Remediate updates