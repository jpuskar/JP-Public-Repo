Import-Module SMLets
$SRClass = Get-SCSMClass System.WorkItem.ServiceRequest$
$IRClass = Get-SCSMClass System.WorkItem.Incident$
$CRclass = Get-SCSMClass -name System.WorkItem.ChangeRequest$
$SRs = Get-SCSMObject -Class $SRclass
$IRs = Get-SCSMObject -Class $IRclass
$CRs = Get-SCSMObject -Class $CRclass

$targetDaysAgo = 150
$ThreeMonthsAgo = (get-date).AddDays(-90)
$i = 0
$aDateWICount = @()

While($i -lt $targetDaysAgo) {
	$curDay = (Get-Date).AddDays((($targetDaysAgo - $i) * -1))
	
	#closed this day
	$countClosed = 0
	$openSRs = $null
	$openSRs = $SRs | ?{$_.CompletedDate -ne $null} | ?{
		(Get-Date $_.CompletedDate).Year -eq (Get-Date $curDay).Year -and `
		(Get-Date $_.CompletedDate).DayOfYear -eq (Get-Date $curDay).DayOfYear
	}
	$countClosed += $openSRs.Count
	
	$openIRs = $null
	$openIRs = $IRs | ?{$_.ResolvedDate -ne $null} | ?{
		(Get-Date $_.ResolvedDate).Year -eq (Get-Date $curDay).Year -and `
		(Get-Date $_.ResolvedDate).DayOfYear -eq (Get-Date $curDay).DayOfYear
	}
	$countClosed += $openIRs.Count
	
	$openCRs = $null
	$openCRs = $CRs | ?{$_.Status.DisplayName -eq "Completed"} | ?{
		(Get-Date $_.LastModified).Year -eq (Get-Date $curDay).Year -and `
		(Get-Date $_.LastModified).DayOfYear -eq (Get-Date $curDay).DayOfYear
	}
	$countClosed += $openCRs.Count
	
	#opened this day
	$countOpened = 0
	$openSRs = $null
	$openSRs = $SRs | ?{
		(Get-Date $_.CreatedDate).Year -eq (Get-Date $curDay).Year -and `
		(Get-Date $_.CreatedDate).DayOfYear -eq (Get-Date $curDay).DayOfYear
	}
	$countOpened += $openSRs.Count
	$openIRs = $null
	$openIRs = $IRs | ?{
		(Get-Date $_.CreatedDate).Year -eq (Get-Date $curDay).Year -and `
		(Get-Date $_.CreatedDate).DayOfYear -eq (Get-Date $curDay).DayOfYear
	}
	$countOpened += $openIRs.Count
	
	$openCRs = $null
	$openCRs = $CRs | ?{
		(Get-Date $_.CreatedDate).Year -eq (Get-Date $curDay).Year -and `
		(Get-Date $_.CreatedDate).DayOfYear -eq (Get-Date $curDay).DayOfYear
	}
	$countOpened += $openCRs.Count
	
	$oDateWICount = New-Object -type PSObject
	$oDateWICount | Add-Member -Type NoteProperty -Name "Date" -Value $curDay
	$oDateWICount | Add-Member -Type NoteProperty -Name "Tickets Closed" -Value $countClosed
	$oDateWICount | Add-Member -Type NoteProperty -Name "Tickets Opened" -Value $countOpened
	$aDateWICount += $oDateWICount
	$i++
}

If((Test-Path "C:\Windows\Logs\orchtemp") -eq $false)
	{mkdir "C:\Windows\Logs\orchtemp"}
If((Test-Path "C:\Windows\Logs\orchtemp\daily-ticket-close-report.csv") -eq $true)
	{remove-item "C:\Windows\Logs\orchtemp\daily-ticket-close-report.csv" -force}
$aDateWICount | Export-CSV "C:\Windows\Logs\orchtemp\daily-ticket-close-report.csv"
#$aDateWICount
