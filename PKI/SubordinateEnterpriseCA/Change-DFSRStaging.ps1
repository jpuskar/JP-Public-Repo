#I want to change the stagingPath parameter of the respective instance of the DfsrReplicatedFolderConfig class
#The staging path is actually stored in AD
$computer = gc env:computername
$targetStagingPath = "G:\dfsr\staging\certdata"

#find the repl folder GUID
$ReplFolderConfigs = $null
$i = 0
While($ReplFolderConfigs -eq $null)
	{
		If($i -gt 0)
			{Sleep -seconds 2}
		ElseIf($i -gt 15)
			{
				$foundFolderConfigs = $false
				Break
			}
		$ReplFolderConfigs = gwmi -namespace "root\MicrosoftDFS" -class DfsrReplicatedFolderConfig
		$i++
	}

If(($ReplFolderConfigs.GetType().BaseType.Name) -eq "Array")
	{
		$ReplFolderConfigs | % {
			write-host -f cyan $_.RootPath
			If($_.RootPath -like "*inetPub*CertData*" -and $_.StagingPath -like "*inetPub*CertData*")
				{$replFolder = $_}
		}
	}
Else
	{$replFolder = $ReplFolderConfigs}
$folderGUID = $ReplFolder.ReplicatedFolderGuid

write-host -f cyan "folderGuid: $folderGUID"

#grab the objet from AD
$strFilter = "(&(objectClass=msDFSR-Subscription)(CN=" + $folderGUID + "))"
$objDomain = New-Object System.DirectoryServices.DirectoryEntry
$objSearcher = New-Object System.DirectoryServices.DirectorySearcher
$objSearcher.SearchRoot = $objDomain
$objSearcher.Filter = $strFilter
$colResults = $objSearcher.FindAll()

If(($colResults.PSBase.GetType().Name) -eq "SearchResult")
	{$sDFSRConfigLDAPPath = $colResults.Path}
Else
	{
		$colResults | % {
			$result = $_
			$ldapResult = $result.Path
#			write-host -f green $ldapResult
			If($ldapResult -like ("*" + $computer + "*"))
				{$sDFSRConfigLDAPPath = $ldapResult}
		}
	}

#write-host -f yellow "sDFSRConfigLDAPPath: $sDFSRConfigLDAPPath"
$objDFSRConfig = [adsi]$sDFSRConfigLDAPPath

#modify the property
$stagepath = $objDFSRConfig.Get("msDFSR-StagingPath")
#write-host -f yellow "Current staging path: $stagepath"
$objDFSRConfig.Put("msDFSR-StagingPath",$targetStagingPath)
$objDFSRConfig.SetInfo()

#restart the dfsr service
Restart-Service DFSR
Sleep -seconds 10