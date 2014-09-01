##ref: http://techchucker.wordpress.com/2013/02/21/outputsplist/
##ref: http://markimarta.com/sharepoint/delete-all-items-in-sharepoint-list-using-powershell/

#Region SP Output File Variables
$inputCSV = import-csv Change-Management-Report.csv

$webURL = "http://sharepoint1.osuesl.net/sites/esl-it"
$listName = "IT Change Management Billboard"

#Get the SPWeb object and save to variable
$listWeb = Get-SPWeb $webURL

#Get the SPList object to retrieve the list
$list = $listWeb.Lists[$listName]
#endRegion

#Region Web Application Variable
$Siteurl = "http://sharepoint1/sites/esl-it"
$Rootweb = New-Object Microsoft.Sharepoint.Spsite($Siteurl);
$Webapp = $Rootweb.Webapplication;
#endRegion

#clear current list
$listItems = $list.Items
$count = $listItems.Count - 1
for($intIndex = $count; $intIndex -gt -1; $intIndex--) 
	{$listItems.Delete($intIndex)}

$inputCSV | % {
	$newItem = $null
	$newItem = $list.Items.Add()
	$newItem["Title"] = $_.Title
	$newItem["Description"] = $_.Description
	$newItem["Reason"] = $_.Reason
	$newItem["Work Item ID"] = $_.ID
	$newItem["Implementation Plan"] = $_.ImplementationPlan
	$newItem["Test Plan"] = $_.TestPlan
	$newItem["Backout Plan"] = $_.BackoutPlan
	$newItem["Risk Assessment Plan"] = $_.RiskAssessmentPlan
	$newItem["Implementation Results"] = $_.ImplementationResults
	$newItem["Classification"] = $_.Area
	$newItem["Status"] = $_.Status
	$newItem.Update()
}

