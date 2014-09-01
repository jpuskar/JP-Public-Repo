#dictionary of urgency / priority to weight

Function Construct-PriorityRelationship($priority,$urgency,$initWeight,$srDailyMultiplier) {
	$newRelationship = $null
	$newRelationship = New-Object -typename PSObject
	$newRelationship | Add-Member -MemberType NoteProperty -Name Priority -Value $priority
	$newRelationship | Add-Member -MemberType NoteProperty -Name Urgency -Value $urgency
	$newRelationship | Add-Member -MemberType NoteProperty -Name StartingWeight -Value $initWeight
	$newRelationship | Add-Member -MemberType NoteProperty -Name SRDailyMultiplier -Value $srDailyMultiplier
	Return $newRelationship
}

Function Construct-PriorityRelationshipsArray() {
	$aRelationships = $null
	$aRelationships = @()
	
	#start adding
	$aRelationships += Construct-PriorityRelationship "Override" "Immediate" 5000 4
	$aRelationships += Construct-PriorityRelationship "Override" "Urgent" 5000 4
	$aRelationships += Construct-PriorityRelationship "Faculty" "Immediate" 1000 4
	$aRelationships += Construct-PriorityRelationship "Faculty" "Urgent" 500 2
	$aRelationships += Construct-PriorityRelationship "Staff" "Immediate" 1000 4
	$aRelationships += Construct-PriorityRelationship "Staff" "Urgent" 450 2
	$aRelationships += Construct-PriorityRelationship "Grad" "Immediate" 800 4
	$aRelationships += Construct-PriorityRelationship "Grad" "Urgent" 400 2
	$aRelationships += Construct-PriorityRelationship "Override" "Routine" 800 2
	$aRelationships += Construct-PriorityRelationship "Override" "Low" 800 2
	$aRelationships += Construct-PriorityRelationship "Faculty" "Routine" 300 1.5
	$aRelationships += Construct-PriorityRelationship "Staff" "Routine" 250 1.5
	$aRelationships += Construct-PriorityRelationship "Grad" "Routine" 200 1.5
	$aRelationships += Construct-PriorityRelationship "Faculty" "Low" 100 1.1
	$aRelationships += Construct-PriorityRelationship "Staff" "Low" 100 1.1
	$aRelationships += Construct-PriorityRelationship "Grad" "Low" 100 1.1
	
	Return $aRelationships
}

Function Construct-AreaSLOHash() {
	$hAreaToSLOHours = @{}
	$hAreaToSLOHours.Add("Documentation",3)
	$hAreaToSLOHours.Add("Access Control",1)
	$hAreaToSLOHours.Add("Server Configuration Change",6)
	$hAreaToSLOHours.Add("Workstation Configuration Change",1)
	$hAreaToSLOHours.Add("Data Recovery",3)
	$hAreaToSLOHours.Add("Add Package to SCCM",3)
	$hAreaToSLOHours.Add("New Server Install",3)
	$hAreaToSLOHours.Add("Purchase and Install Software (eStores)",2)
	$hAreaToSLOHours.Add("Software Install (manual)",2)
	$hAreaToSLOHours.Add("Printer Consumables",1)
	$hAreaToSLOHours.Add("Computer Reinstall",5)
	$hAreaToSLOHours.Add("Repurposed Equipment",1)
	$hAreaToSLOHours.Add("New Account Request",1)
	$hAreaToSLOHours.Add("IT Service Question or Suggestion",2)
	$hAreaToSLOHours.Add("Exit Processing or Deprovision User",2)
	$hAreaToSLOHours.Add("Software Install (SCCM, Casper, or RHSS)",1)
	Return $hAreaToSLOHours
}

#___________________________________


Function Get-ServiceRequests() {
	$srClass = Get-SCSMClass -name System.WorkItem.ServiceRequest$
	$srEnCompleteId = (Get-SCSMEnumeration ServiceRequestStatusEnum.Completed).Id
#	$activeSrList = Get-SCSMObject –Class $srClass -Filter "Status -ne $srEnCompleteId" | ?{`
#		$_.Status.Name -eq "ServiceRequestStatusEnum.InProgress"`
#		-or $_.Status.Name -eq "ServiceRequestStatusEnum.Submitted"`
#		-or $_.Status.Name -eq "ServiceRequestStatusEnum.New"`
#	}
	$activeSrList = Get-SCSMObject –Class $srClass
	
	Return $activeSRList
}

Function Get-IncidentRequests() {
	$irClass = Get-SCSMClass -name System.WorkItem.Incident$
	$irEnResolvedId = (Get-SCSMEnumeration IncidentStatusEnum.Resolved$).Id
	#$activeIrList = Get-SCSMObject –Class $irClass -Filter "`
	#	Status -ne $irEnResolvedId" | ?{`
	#		$_.Status.Name -ne "IncidentStatusEnum.Resolved"`
	#}
	$activeIrList = Get-SCSMObject –Class $irClass
	
	Return $activeIrList
}

Function Normalize-ServiceRequests($activeSRList) {
	$AffectedUserRelClass = Get-SCSMRelationshipClass System.WorkItemAffectedUser$
	$aNormalizedSRs = $null
	$aNormalizedSRs = @()
	
	$activeSRList | % {
		$curSR = $null
		$curSR = $_
		
		#user
		$AffectedUser = $null
		$AffectedUser = Get-SCSMRelatedObject -SMObject $curSR -Relationship $AffectedUserRelClass
		$username = $null
		$username = $AffectedUser.DisplayName
		
		#daysOld
		$daysOldTS = $null
		$daysOld = $null
		If($curSR.Status.DisplayName -eq "In Progress" -or $curSR.Status.DisplayName -eq "Active") {
			$daysOldTS = New-TimeSpan -Start $curSR.CreatedDate -End (Get-Date)
			$daysOld = $daysOldTS.Days
		}
		
		$extendedSR = $null
		$extendedSR = New-Object -TypeName PSObject
		$extendedSR | Add-Member -MemberType NoteProperty -Name ID -Value $curSR.ID
		$extendedSR | Add-Member -MemberType NoteProperty -Name Requester -Value $username
		$extendedSR | Add-Member -MemberType NoteProperty -Name DaysOld -Value $DaysOld
		$extendedSR | Add-Member -MemberType NoteProperty -Name Title -Value $curSR.Title
		$extendedSR | Add-Member -MemberType NoteProperty -Name Area -Value $curSR.Area.DisplayName
		$extendedSR | Add-Member -MemberType NoteProperty -Name Urgency -Value $curSR.Urgency.Displayname
		$extendedSR | Add-Member -MemberType NoteProperty -Name Priority -Value $curSR.Priority.DisplayName
		$extendedSR | Add-Member -MemberType NoteProperty -Name Status -Value $curSR.Status.DisplayName
		
		$aNormalizedSRs += $extendedSR
	}
	Return $aNormalizedSRs
}

Function Normalize-IncidentRequests($activeIRList) {
	$AffectedUserRelClass = Get-SCSMRelationshipClass System.WorkItemAffectedUser$
	$aNormalizedIRs = $null
	$aNormalizedIRs = @()
	
	$activeIRList | % {
		#get current sr
		$curIR = $null
		$curIR = $_
		
		#user
		$AffectedUser = $null
		$AffectedUser = Get-SCSMRelatedObject -SMObject $curIR -Relationship $AffectedUserRelClass
		$username = $null
		$username = $AffectedUser.DisplayName
		
		#daysOld
		$daysOldTS = $null
		$daysOld = $null
		If($curIR.Status.DisplayName -eq "In Progress" -or $curIR.Status.DisplayName -eq "Active") {
			$daysOldTS = New-TimeSpan -Start $curIR.CreatedDate -End (Get-Date)
			$daysOld = $daysOldTS.Days
		}
		
		#status
		$status = $null
		$status = $curIR.Status.Displayname
		If($status -eq "Active"){$status = "In Progress"}
		ElseIf($status -eq "Resolved"){$status = "Completed"}
		
		$extendedIR = $null
		$extendedIR = New-Object -TypeName PSObject
		$extendedIR | Add-Member -MemberType NoteProperty -Name ID -Value $curIR.ID
		$extendedIR | Add-Member -MemberType NoteProperty -Name Requester -Value $username
		$extendedIR | Add-Member -MemberType NoteProperty -Name DaysOld -Value $DaysOld
		$extendedIR | Add-Member -MemberType NoteProperty -Name Title -Value $curIR.Title
		$extendedIR | Add-Member -MemberType NoteProperty -Name Area -Value $curIR.Area.DisplayName
		$extendedIR | Add-Member -MemberType NoteProperty -Name Urgency -Value $curIR.Urgency.Displayname
		$extendedIR | Add-Member -MemberType NoteProperty -Name Priority -Value $curIR.Impact.DisplayName
		$extendedIR | Add-Member -MemberType NoteProperty -Name Status -Value $status
		$aNormalizedIRs += $extendedIR
	}
	Return $aNormalizedIRs

}
Function Lookup-InitialWeight($aPriorityRelationships,$priority,$urgency) {
	$affectedRelationship = $null
	$affectedRelationship = $aPriorityRelationships | ?{`
		$_.Priority -eq $Priority`
		-and $_.Urgency -eq $Urgency}
	
	$initWeight = $null
	$initWeight = $affectedRelationship.StartingWeight
	Return $initWeight
}

Function Lookup-DailyWeight($aPriorityRelationships,$priority,$urgency) {
	$affectedRelationship = $null
	$affectedRelationship = $aPriorityRelationships | ?{`
		$_.Priority -eq $priority`
		-and $_.Urgency -eq $Urgency}
	
	$daily = $null
	$daily = $affectedRelationship.SRDailyMultiplier
	Return $daily
}

Function Weigh-WorkItem ($workItem,$aPriorityRelationships) {
	$priority = $null
	$priority = $workItem.Priority
	$urgency = $null
	$urgency = $workItem.Urgency
	
	$initialWeight = Lookup-InitialWeight $aPriorityRelationships $priority $urgency
	$dailyMultiplier = Lookup-DailyWeight $aPriorityRelationships $priority $urgency
	$daysOld = $workItem.DaysOld
	#write-host -f yellow "priority: $priority`nUrgency: $urgency`ninitialweight: $initialweight`nDailyWeight: $dailyMultiplier"
	$daysOldWeightAdjustment = $daysOld * ($initialWeight * $dailyMultiplier)
	$adjustedWeight = $initialWeight + $daysOldWeightAdjustment

	Return $adjustedWeight
}

Function Weigh-WorkItems ($normalizedWIList,$aPriorityRelationships) {
	$aPriorityRelationships = $null
	$aPriorityRelationships = Construct-PriorityRelationshipsArray
	
	#add weight
	$aWeightedWIList = $null
	$aWeightedWIList = @()
	$normalizedWIList | % {
		$currentWI = $_
		
		$adjustedWeight = $null
		If($currentWI.Status -ne "In Progress" -and $currentWI.Status -ne "Active") {}
		Else {
			$priority = $null
			$priority = $currentWI.Priority
			$urgency = $null
			$urgency = $currentWI.Urgency
			
			$adjustedWeight = $null
			$adjustedWeight = Weigh-WorkItem $currentWI $aPriorityRelationships
		}
		
		$scoredWI = $currentWI
		$scoredWI | Add-Member -MemberType NoteProperty -Name Weight -Value $adjustedWeight
		$aWeightedWIList += $scoredWI
	}
	
	Return $aWeightedWIList
}

Function Get-TargetDeliveryDate ($workHoursNeeded, $hoursPerDay) {
	$workDaysNeeded = 0
	
	While($workHoursNeeded -gt $hoursPerDay) {
		$curDate = $null
		$curDate = (get-date).AddDays($workDaysNeeded)
		
		#compensate for sat/sun
		If ($curDate.DayOfWeek.Value__ -eq 6) {$workDaysNeeded++;$workDaysNeeded++}
		ElseIf ($curDate.DayOfWeek.Value__ -eq 0) {$workDaysNeeded++}
		Else {
			$workDaysNeeded++
			$workHoursNeeded = $workHoursNeeded - 10
		}
	}
	
	$propsedFinalDate = (Get-Date).AddDays($workDaysNeeded)
	If ($propsedFinalDate.DayOfWeek.Value__ -eq 6) {$workDaysNeeded++;$workDaysNeeded++}
	ElseIf ($propsedFinalDate.DayOfWeek.Value__ -eq 0) {$workDaysNeeded++}
	
	$finalDate = $null
	$finalDate = (Get-Date).AddDays($workDaysNeeded)
	
	Return $finalDate
}

Function Add-DatesToWiTable($sortedWiTable,$hAreaToSloKeys) {
	$hAreaToSLOHours = $null
	$hAreaToSLOHours = Construct-AreaSLOHash
	
	$sortedTableWithDDays = $null
	$sortedTableWithDDays = @()
	$runningTotalOfWIWorkHours = 0
	$WIWorkHoursPerDay = 10
	
	$sortedWiTable | % {
		$targetDDString = $null
		$curWI = $null
		$curWI = $_
		If($curWI.Status -ne "In Progress" -and $curWI.Status -ne "Active") {}
		Else {
			
			$SLOkeys = $null
			$SLOkeys = $hAreaToSloHours.Keys
			If($SLOKeys -contains ($curWI.Area)) {
				$runningTotalOfWIWorkHours += ($hAreaToSloHours.Get_Item($curWI.Area))
			}
			Else {$runningTotalOfWIWorkHours += 5}
			
			$targetDeliveryDate = $null
			$targetDeliveryDate = Get-TargetDeliveryDate $runningTotalOfWIWorkHours $WIWorkHoursPerDay
			$targetDDString = $null
			$targetDDString = Get-Date $targetDeliveryDate -format "MM/dd/yyyy"
		}
		
		$newWI = $null
		$newWI = $curWI
		$newWI | Add-Member -MemberType NoteProperty -Name ExpectedDeliveryDate -Value $targetDDString
		$sortedTableWithDDays += $newWI
	}
	
	Return $sortedTableWithDDays
}

$activeSRList = $null
$activeSRList = Get-ServiceRequests

$activeIRList = $null
$activeIRList = Get-IncidentRequests

#IR's have 'impact', which is basically the same as priority.
#the normalize functions turn SR/IR SCSM classes into a custom object we create.
$normalizedIRList = $null
$normalizedIRList = Normalize-IncidentRequests $activeIrList
$normalizedSRList = $null
$normalizedSRList = Normalize-ServiceRequests $activeSrList

#merge sr's/ir's into wi's
$normalizedWIList = $null
$normalizedWIList = $normalizedIRList + $normalizedSRList

$weightedWIList = $null
$weightedWIList = Weigh-WorkItems $normalizedWIList

$sortedWiTable = $null
$sortedWiTable = $weightedWIList | sort weight -descending

#Get delivery date
$datedWITable = $null
$datedWITable = Add-DatesToWiTable $sortedWiTable

$datedWITable | Export-CSV Service-and-Incident-Report.csv