######################################################################################
#Script Name: Get-DriverPackageInfo.ps1
#Authored By: Robert Holbert - Holbert.26@Chemistry.Ohio-State.edu
#Created On: 9/19/2012
#Function: Checks For Changes in Driver Packages and Pushes any Changes to GitHub Repo
######################################################################################


##Variables
$GitPath = "C:\GitHub\ASC-SCCM-Private"
$gitUsername = "ASC-SCCM-Robot"
$gitEmail = "win-team@chem.osu.edu"
$driverPackagePath = $GitPath + "\DriverPackages\"
$logFileRoot = "C:\logs\Get-DriverPackageInfo\"
$PasswordPath = "C:\Scripts\Get-DriverPackageInfo\GitPassword.txt"
$GitPasswd = get-content $PasswordPath
$WebRepositoryPath = "github.com/ASCTech/ASC-SCCM-Private.git"
$AuthWebRepositoryPath = "https://" + $GitUsername + ':' + $GitPasswd + '@' + $WebRepositoryPath

If((Test-Path $GitPath) -eq $false)
	{
		$msg = "Repo root path DNE (" + $GitPath + ")."
		Write-host -f magenta
		Exit
	}


##LOG FILE FUNCTION Code REF - http://powershellcommunity.org/Forums/tabid/54/aft/4700/Default.aspx  
function write-log([string]$info){
    if($loginitialized -eq $false){            
        $FileHeader | Out-File $logfile -Append -Confirm:$false -encoding "UTF8"          
        $script:loginitialized = $True            
    }            
    $info | Out-File $logfile -Append -Confirm:$false -encoding "UTF8"
}            
   
##############################################################################

Function WriteDriverPackageToFile($ThisDriverPackage)
{
trap [Exception] { 
      write-log
      write-log $("TRAPPED: " + $_.Exception.GetType().FullName); 
      write-log $("TRAPPED: " + $_.Exception.Message); 
      continue; 
	  }
	  
	  ##Writing Driver Package Header
	  $PackageID = $ThisDriverPackage.PackageID
	  $PackageName = $ThisDriverPackage.Name
	  $PkgSourcePath = $ThisDriverPackage.PkgSourcePath
	  $lineToWrite = "Driver Name" + ',' + "Driver Source Path" + ',' + "Driver Version" + ',' + "Driver PackageID" + ',' + "Driver Package Name" + ',' + "Driver Package Source Path"
	  $fileName = $driverPackagePath + $PackageID + ".txt"
	  $logLine = "Getting Driver Info For Package " + $PackageID
	  write-log $logLine
	  
	  #Check if driver package is new
	  $changesMade = $false
	  if((Test-Path $filename) -eq $false) {
		$changesMade = $true
		$logLine = "Package: " + $PackageID + " is a new package."
		$ChangeMSG = "(NEW PACKAGE) " + $PackageID + " - " + $PackageName + ", "
		write-log $logLine
	}
		
	  $oldFile = Get-Content $fileName
	  $lineToWrite | Out-File $fileName -Confirm:$false -encoding "UTF8"
	  ##Writing Driver Info For Package
		if($PackageIDToContentID.ContainsKey($PackageID)) {
			$CIDs = $PackageIDToContentID.Get_Item($PackageID)
			foreach($CID in $CIDs) {
				if($ContentIDToCIID.ContainsKey($CID)) {
					$CIIDs = $ContentIDToCIID.Get_Item($CID)
					foreach($CIID in $CIIDs) {
						foreach($i in $drivers) {
							if($i.CI_ID -eq $CIID) {
								$Name = $i.LocalizedDisplayName
								$Source = $i.ContentSourcePath
								$Ver = $i.DriverVersion
								$lineToWrite = $Name + ',' + $Source + ',' + $Ver + ',' + $PackageID + ',' + $PackageName + ',' + $PkgSourcePath
								$lineToWrite | Out-File $filename -append -confirm:$false -encoding "UTF8"
							}
						}
					}
				}
			}
		}

		if(!$changesMade) {
		  #CompareFiles
		  $newFile = Get-Content $fileName
		  $diff = diff $oldFile $newFile
		  if($diff.count -gt 0) {
			$changesMade = $true
			$logLine = "Changes have been made to " + $PackageID + ".txt"
			$ChangeMSG = "(changed) " + $PackageID + " - " + $PackageName + ", "
			write-log $logLine
		}
	}
  $retval = @()
  $retval += $changesMade
  $retval += $ChangeMSG
  Return $retval
}

##########################################################################################
<#---------Logfile Info----------#>            #Code REF - http://powershellcommunity.org/Forums/tabid/54/aft/4700/Default.aspx
$logfileFullName = $logFileRoot.TrimEnd("\\") + "\Get-DriverPackageInfo-" + $(get-date -format MMddyyHHmmss) + ".log"
$script:logfile = $logfileFullName
$script:Seperator = @"

$("-" * 25)

"@            
$script:loginitialized = $false            
$script:FileHeader = @"
$seperator
***Application Information***
Filename:  Get-DriverPackageInfo.ps1
Created by:  Holbert.26
"@       

# Aliases for Get-LogicalDisk
	set-alias -name Get-Storage -value Get-LogicalDisk -Scope Global -Option AllScope -Description "Alias for get-logicaldisk."
	set-alias -name st -value Get-LogicalDisk -Scope Global -Option AllScope -Description "Alias for get-logicaldisk."

############################################################################################
	
##Main	
trap [Exception] { 
		write-host -f magenta $("TRAPPED: " + $_.Exception.GetType().FullName); 
    write-host -f magenta $("TRAPPED: " + $_.Exception.Message); 
    
      write-log
      write-log $("TRAPPED: " + $_.Exception.GetType().FullName); 
      write-log $("TRAPPED: " + $_.Exception.Message); 
      continue; 
}

##Get SCCM Driver Packages, Drivers, And Linking Files
write-log "Getting SCCM Driver Packages"
$driverPacks = Get-WmiObject SMS_DriverPackage -namespace root\sms\site_chm
write-log "Getting SCCM Drivers"
$drivers = Get-WmiObject SMS_Driver -namespace root\sms\site_chm
write-log "Getting PackageToContent"
$PTC = Get-WmiObject SMS_PackageToContent -namespace root\sms\site_chm
write-log "Getting CIToContent"
$CITC = Get-WmiObject SMS_CIToContent -namespace root\sms\site_chm
$changesMade = $false #Variable to track if changes were made and if so a commit is needed
##Create Maps of Data
$PackageIDToContentID = @{($PTC[0].PackageID) = @($PTC[0].ContentID)}
foreach ($P in $PTC) {
	if($PackageIDToContentID.ContainsKey($P.PackageID)) {
		$PackageIDToContentID.Set_Item($P.PackageID,$PackageIDToContentID.Get_Item($P.PackageID)+$P.ContentID)
	} else {
		$PackageIDToContentID.Add($P.PackageID,@($P.ContentID))
	}
}
$ContentIDToCIID = @{($CITC[0].ContentID) = ($CITC[0].CI_ID)}
foreach($C in $CITC) {
	if($ContentIDToCIID.ContainsKey($C.ContentID)) {
		$ContentIDToCIID.Set_Item($C.ContentID,$ContentIDToCIID.Get_Item($C.ContentID)+$C.CI_ID)
	} else {
		$ContentIDToCIID.Add(($C.ContentID),@($C.CI_ID))
	}
}

#Create Change Message
$ChangeMSG = "The Following Changes Have Been Made: "

$driverPackageIDs = @()

##Output Data For Each Driver Package
foreach ($i in $driverPacks) 
    {
		$results = WriteDriverPackageToFile($i)
		if($results[0] -eq $true) {
			$changesMade = $true
			$changeMSG = $changeMSG + $results[1]
		}
		$driverPackageIDs += $i.PackageID
	}	

#Check For Deleted Packages as Files
##$driverPackagePath - Set Only At the Top
$driverPackageFiles = ls $driverPackagePath
$filesToRMFromGit = @()
foreach ($file in $driverPackageFiles) {
	if(!($driverPackageIDs -contains $file.BaseName)) {
		$PkgCont = Import-Csv $file.FullName
		$PackageName = ($PkgCont[0]."Driver Package Name")
		$ChangeMSG += "(REMOVED PACKAGE) " + $file.BaseName + " - " + $PackageName + ','
		$logLine = "Driver Package: " + $file.BaseName + " no longer exists, deleting file."
		write-log $logLine
		$filesToRMFromGit += $file.FullName
		$changesMade = $true
	}
}

#convert all .txt files in repo files to UTF-8
$txtFiles = ls $gitPath | where {$_.Name -like "*.txt"} | % {
	#$newname = $_.FullName + ".utf8"
	(Get-Content -Path $_.FullName) | Set-Content -Encoding "UTF8" $_.FullName
}

#Commit to Git
if($changesMade) {
	write-log $ChangeMSG
	$logLine = "Committing Changes to Git"
	write-log $logLine
	
	#username and email set at top
	git config --global user.name $gitUsername
	git config --global user.email $gitEmail

	##$GitPath - Set Only At The Top
	cd $GitPath
	git init
	##$driverPackagePath - Set only at the top
	git add $driverPackagePath
	foreach ($fileName in $filesToRMFromGit) {
		git rm $fileName
	}
	git commit -m $ChangeMSG
	#git remote add origin https://github.com/ASCTech/ASC-SCCM-Private.git
	git push -u $AuthWebRepositoryPath master
	} else {
		write-log "No Changes Have Been Made"
	}

write-log "Complete"
	
