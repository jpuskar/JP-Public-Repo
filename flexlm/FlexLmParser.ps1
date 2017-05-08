$optionsFilePath = $args[0]
$lmstatOutputFile = $args[1]
$scriptCSVOutputFilename = $args[2]

$lmstatOutput = gc $lmstatOutputFile

$script:optionsFilePath = $null
$script:optionsFilePath = $optionsFilePath
$script:currentFeature = $null
$script:currentGroup = $null
	
$LMFeatures = $null
$LMFeatures = @()

$LMFeatureReservations = $null
$LMFeatureReservations = @()

$LMFeatureReservationInstances = $null
$LMFeatureReservationInstances = @()

Function Generate-UserGroupMap() {
	$optionsGroups = $null
	$optionsGroups = @()
	
	$optionsFile = Get-Content $script:OptionsFilePath
	
	$optionsFile | % {
		$curLine = $null
		$curLine = $_
		If($curLine -like "GROUP *") {
			$aLine = $null
			$aLine = $curLine.Split(" ")
			$groupName = $aLine[1]
			$users = $null
			$users = @()
			$aLine | % {
				If($_ -notlike $aLine[0] -and $users -notcontains $_) {
					$users += $_
				}
			}
			
			$optionsGroup = $null
			$optionsGroup = New-Object PSObject
			$optionsGroup | Add-Member -type NoteProperty -Name GroupName -Value $groupName
			$optionsGroup | Add-Member -type NoteProperty -Name Users -Value $users
			$optionsGroups += $optionsGroup
		}
	}
	
	#CLASS OptionGroups
	#Property UserArray
	
	Return $optionsGroups
}

Function Generate-GroupReservationMap {
	$optionsFile = Get-Content $script:OptionsFilePath
	
	$GroupReservations = $null
	$GroupReservations = @()
		
	$optionsFile | % {
		$curLine = $null
		$curLine = $_
		If($curLine -like "RESERVE*") {
			$aLine = $null
			$aLine = $curLine.Split(" ")
			$quantity = $null
			[int32]$quantity = $aLine[1].Trim()
			#write-host -f green """$quantity"""
			
			$featureName = $null
			$featureName = ($aLine[2].Split(":"))[0]
			
			$featureVersion = $null
			$featureVersion = ($aLine[2].Split(":"))[1].Replace("VERSION=""","").TrimEnd("""")
			
			$groupName = $null
			$groupName = $aLine[4]
			
			$GroupReservation = $null
			$GroupReservation = New-Object PSObject
			$GroupReservation | Add-Member -Type NoteProperty -Name "GroupName" -Value $groupName
			$GroupReservation | Add-Member -Type NoteProperty -Name "Quantity" -Value $quantity
			$GroupReservation | Add-Member -Type NoteProperty -Name "FeatureName" -Value $featureName
			$GroupReservation | Add-Member -Type NoteProperty -Name "FeatureVersion" -Value $featureVersion
			$GroupReservations += $GroupReservation
		}
	}
	
	Return $groupReservations
}


$oUserGroupMap = $null
$oUserGroupMap = Generate-UserGroupMap

$oGroupReservations = $null
$oGroupReservations = $null = Generate-GroupReservationMap
#$oGroupReservations


$lmstatOutput | % {
	$curLine = $null
	$curLine = $_
	
	If($curLine -like "*Users of *") {
#		Class LMFeature
#			Property FeatureName
#			Property LicensesIssued
#			Property LicensesInUse
#			Child Class Reservations
		
		$sLine = $null
		$sLine = $curLine
		
		$sLine = $sLine.Replace("  "," ")
		$aLine = $null
		$aLine = $sLine.Split(" ")
		
		$featureName = $null
		$featureName = $aLine[2].Replace(":","")
		
		$LicensesIssued = $null
		$LicensesIssued = $aLine[5]
		
		$LicensesInUse = $null
		$LicensesInUse = $aLine[10]
		
		$LMFeature = $null
		$LMFeature = New-Object PSObject
		$LMFeature | Add-Member -Type NoteProperty -Name FeatureName -Value $featureName
		$LMFeature | Add-Member -Type NoteProperty -Name LicensesIssued -Value $licensesIssued
		$LMFeature | Add-Member -Type NoteProperty -Name LicensesInUse -Value $licensesInUse
		$LMFeatures += $LMFeature
		
		$script:currentFeature = $featureName
	}
	ElseIf($curLine -like "*RESERVATION for*" -or $curLine -like "*RESERVATIONs for*") {}
	ElseIf($curLine -notlike "*copyright (c)*" -and `
		$curLine -notlike "*flexible license*" -and `
		$curLine.Trim().Split(" ").Count -gt 6) {
		#The "If" block starts here. Funny indenting; sorry.
		
#		Class LMFeature.Reservations.Reservation
#		Property Username
#		Property ClientHostname
#		Property ServerHostname
#		Property FeatureVersion
#		Property LicenseServerAndPort
#		Property LicenseServerDaemonPort
#		Property LicenseCheckoutDateTime
#		Property GroupName

		$sLine = $curLine
		$sLine = $sLine.Trim()
		#$sLine = "SYSTEM ESL0360 ESL0360 (v2012.1009) (license1.osuesl.net/27000 4424), start Mon 10/6 9:13"
		
		$aLine = $null
		$aLine = $sLine.Split(" ")
		
		$Username = $null
		$Username = $aLine[0]
		
		$userGroup = $null
		$userGroup = ($oUserGroupMap | ?{$_.Users -contains $username} | Select -First 1).GroupName
		
		$ClientHostname = $null
		$ClientHostname = $aLine[1]
		
		$indexAdjust = $null
		$indexAdjust = 0
		$ServerHostname = $null
		If($aLine[2] -like "*(*")	{
				$indexAdjust = -1
		}
		Else{$ServerHostname = $aLine[2]}
		
		$FeatureVersion = $null
		$FeatureVersion = $aLine[(3 + $indexAdjust)]
		
		$LicenseServerAndPort = $null
		$LicenseServerAndPort = $aLine[(4 + $indexAdjust)].TrimStart("(")
		
		$LicenseServerDaemonPort = $null
		$LicenseServerDaemonPort = $aLine[(5 + $indexAdjust)].TrimEnd("),")
		
		$LicenseCheckoutDateTime = $null
		$LicenseCheckoutDateTime = $aLine[(8 + $indexAdjust)] + " " + $aLine[(9 + $indexAdjust)]
		
		$LMFeatureReservationInstance = $null
		$LMFeatureReservationInstance = New-Object PSObject
		$LMFeatureReservationInstance | Add-Member -Type NoteProperty -Name FeatureName -Value $script:currentFeature
		$LMFeatureReservationInstance | Add-Member -Type NoteProperty -Name GroupName -Value $userGroup
		$LMFeatureReservationInstance | Add-Member -Type NoteProperty -Name Username -Value $Username
		$LMFeatureReservationInstance | Add-Member -Type NoteProperty -Name ClientHostname -Value $ClientHostname
		$LMFeatureReservationInstance | Add-Member -Type NoteProperty -Name ServerHostname -Value $ServerHostname
		$LMFeatureReservationInstance | Add-Member -Type NoteProperty -Name FeatureVersion -Value $FeatureVersion
		$LMFeatureReservationInstance | Add-Member -Type NoteProperty -Name LicenseServerAndPort -Value $LicenseServerAndPort
		$LMFeatureReservationInstance | Add-Member -Type NoteProperty -Name LicenseServerDaemonPort -Value $LicenseServerDaemonPort
		$LMFeatureReservationInstance | Add-Member -Type NoteProperty -Name LicenseCheckoutDateTime -Value $LicenseCheckoutDateTime
		
		$LMFeatureReservationInstances += $LMFeatureReservationInstance
		
	}
}

#$LMFeatures
#$LMFeatureReservations | sort -property groupName | ft
#$LMFeatureReservationInstances | select Username,featureName,groupName,licenseServerAndPort | sort -property GroupName | ft
#Exit
#counts for licenses in-use by group by feature

#CLASS FinalReport
#Property GroupName
#Property FeatureName
#Property LicensesAvailable
#Property LicensesInUse

$FinalReport = $null
$FinalReport = @()

$LMFeatures | % {
	$featureName = $_.FeatureName
	$UsageInstances = $LMFeatureReservationInstances | ?{$_.FeatureName -eq $featureName}
	
	$groupList = $null
	$groupList = @()
	$oGroupReservations | % {If($groupList -notcontains $_.GroupName){$groupList += $_.GroupName}}
	
	$groupList | % {
		$curGroupName = $_
		
		#$InUse = $null
		$InUse = 0
		[int32]$InUse = ($LMFeatureReservationInstances | ?{$_.FeatureName -eq $featureName -and $_.GroupName -eq $curGroupName.ToLower()}).Count
		
		#$quantity = $null
		$quantity = 0
		$quantity = ($oGroupReservations | ?{$_.GroupName.ToLower() -eq $curGroupName.ToLower() -and $_.FeatureName -eq $featureName} | sort -property quantity | select -first 1).Quantity
		If($quantity -eq $null){$quantity = 0}
		#Write-Host """$quantity"""
		
		#$quantity; $InUse
		
		#$inuse | gm | out-host
		#Exit
		
		#$freeLicenses = $null
		$freeLicenses = 0
		$freeLicenses = $quantity - $InUse
		
		$ReportItem = $null
		$ReportItem = New-Object PSObject
		$ReportItem | Add-Member -Type NoteProperty -Name FeatureName -Value $featureName
		$ReportItem | Add-Member -Type NoteProperty -Name GroupName -Value $curGroupName
		$ReportItem | Add-Member -Type NoteProperty -Name "Total Licenses" -Value $quantity
		$ReportItem | Add-Member -Type NoteProperty -Name "Free Licenses" -Value $freeLicenses
		$finalReport += $reportItem
		
		#Write-Host -f green "Feature: $FeatureName`t$curGroupName`t$quantity`t$free"
	}
}

$finalReport | Export-CSV $scriptCSVOutputFilename