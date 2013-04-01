#stolen from http://thephuck.com/virtualization/powercli-script-to-get-datastore-uuids/
param([string]$vc = "vc" , [string]$vmhost = "vmhost" , [string]$ds = "ds")
#Add-PSSnapin VMware.VimAutomation.Core

function usage() {
	Write-Host -foregroundcolor green "Use this script to get the actual Lun ID of a particular Datastore"
	Write-Host "`n"
	Write-Host -foregroundcolor green "Usage:"
	Write-Host -foregroundcolor yellow "`tGet-LunID -vc  -vmhost  -ds "
	Write-Host "`n"
	Write-Host -foregroundcolor green "The VC hostname must be a hostname for which you have stored credentials (see New-VICredentialStoreItem)!"
	Write-Host -foregroundcolor green "The ESX host must be the full name of a host that can access the Datastore."
	Write-Host "`n"
}

function glid([string]$vmhost,[string]$dsname) {
	$ds = Get-View (Get-View (Get-VMHost -Name $vmhost).ID).ConfigManager.StorageSystem
	foreach ($vol in $ds.FileSystemVolumeInfo.MountInfo) {
#		if ($vol.Volume.Name -eq $dsname) {
			Write-host "DS Name:`t" $vol.Volume.Name
			Write-host "VMFS UUID:`t" $vol.Volume.Uuid
#			foreach ($volid in $vol.Volume.Extent) {
#				foreach ($lun in $ds.StorageDeviceInfo.MultipathInfo.Lun){
#					if ($lun.Id -eq $volid.DiskName) {
#						break
#					}
#				}
#			}
#		Write-Host "LUN Name:`t" $lun.ID
		$mid = $lun.ID
		foreach ($id in $ds.StorageDeviceInfo.ScsiLun) {
#			if ($id.CanonicalName -eq $mid) {
				$uuid = $id.Uuid
#				Write-host "LUN UUID:`t" $uuid
#				}
#			}
		}
	}
}

if (($vc -eq "vc") -or ($vmhost -eq "vmhost") -or ($ds -eq "ds")) {
	usage
} else {
	#$cd = Get-VICredentialStoreItem -host $vc
	#Connect-VIServer -server $cd.host -user $cd.user -password $cd.password
	Write-Host "`n"
	glid $vmhost $ds
	#disconnect-viserver -confirm:$False
}
