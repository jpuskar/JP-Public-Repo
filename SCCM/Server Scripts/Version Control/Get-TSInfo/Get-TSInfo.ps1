######################################################################################
#Script Name: Get-TSInfo.ps1
#Authored By: Robert Holbert - Holbert.26@Chemistry.Ohio-State.edu
#Created On: 9/24/2012
#Function: Checks For Changes in Task Sequences and Pushes any Changes to GitHub Repo
######################################################################################


##Variables
$GitPath = "C:\GitHub\ASC-SCCM-Private"
$gitUsername = "ASC-SCCM-Robot"
$gitEmail = "win-team@chem.osu.edu"
$TSPath = $GitPath + "\TaskSequences\"
$logFileRoot = "C:\logs\Get-TSInfo\"
$PasswordPath = "C:\Scripts\Get-TSInfo\GitPassword.txt"
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

Function WriteTSToFile($ThisTaskSequence)
{
trap [Exception] { 
      write-log
      write-log $("TRAPPED: " + $_.Exception.GetType().FullName); 
      write-log $("TRAPPED: " + $_.Exception.Message); 
      continue; 
	  }
	  
	  ##Writing Driver Package Header
	  $fileName = $TSPath + $ThisTaskSequence.PackageID + ".xml"
	  $PackageName = $ThisTaskSequence.name
	  $PackageID = $ThisTaskSequence.PackageID
	  $logLine = "Getting Driver Info For Task Sequence " + $ThisTaskSequence.PackageID
	  write-log $logLine
	  
	  #Check if driver package is new
	  $changesMade = $false
	  if((Test-Path $filename) -eq $false) {
		$changesMade = $true
		$logLine = "TS: " + $PackageID + " is a new Task Sequence."
		$ChangeMSG = "(NEW PACKAGE) " + $PackageID + " - " + $PackageName + ", "
		write-log $logLine
	}
		
	  $oldFile = Get-Content $fileName
	  #$lineToWrite | Out-File $fileName -Confirm:$false -encoding "UTF8"
	  ##Writing Task Sequence Info
		$Sequence = [wmi]"$($ThisTaskSequence)"
		$Sequence.sequence | Out-File $fileName -Confirm:$false -encoding "UTF8"
		
		#Clean XML - Code Ref - http://www.peter-urda.com/2012/07/ps-clean-up-an-xml-file
		$xml = New-Object Xml
		$xml.Load($fileName)
		$xml.Save($fileName)
		
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
$logfileFullName = $logFileRoot.TrimEnd("\\") + "\Get-TSInfo-" + $(get-date -format MMddyyHHmmss) + ".log"
$script:logfile = $logfileFullName
$script:Seperator = @"

$("-" * 25)

"@            
$script:loginitialized = $false            
$script:FileHeader = @"
$seperator
***Application Information***
Filename:  Get-TSInfo.ps1
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

##Get SCCM TaskSequences
write-log "Getting SCCM TaskSequences"
$taskSequences = Get-WmiObject SMS_TaskSequencePackage -namespace root\sms\site_chm

$changesMade = $false #Variable to track if changes were made and if so a commit is needed

#Create Change Message
$ChangeMSG = "The Following Changes Have Been Made: "

$taskSequencePackageIDs = @()

##Output Data For Each Driver Package
foreach ($i in $taskSequences) 
    {
		$results = WriteTSToFile($i)
		if($results[0] -eq $true) {
			$changesMade = $true
			$changeMSG = $changeMSG + $results[1]
		}
		$taskSequencePackageIDs += $i.PackageID
	}	

#Check For Deleted Packages as Files
##$TSPath - Set Only At the Top
$TSFiles = ls $TSPath
$filesToRMFromGit = @()
foreach ($file in $TSFiles) {
	if(!($taskSequencePackageIDs -contains $file.BaseName)) {
	#	$PkgCont = Import-Csv $file.FullName
	#	$PackageName = ($PkgCont[0]."Driver Package Name")
		$ChangeMSG += "(REMOVED PACKAGE) " + $file.BaseName #+ " - " + $PackageName + ','
		$logLine = "TS Package: " + $file.BaseName + " no longer exists, deleting file."
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
	git add $TSPath
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
	
