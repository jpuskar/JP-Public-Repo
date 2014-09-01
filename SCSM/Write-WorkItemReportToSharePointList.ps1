##ref: http://techchucker.wordpress.com/2013/02/21/outputsplist/
##ref: http://markimarta.com/sharepoint/delete-all-items-in-sharepoint-list-using-powershell/

#Region SP Output File Variables
$inputCSV = Import-CSV Service-and-Incident-Report.csv

$webURL = "http://sharepoint1.osuesl.net/sites/esl-it"
$listName = "IT Request Billboard"

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
For($intIndex = $count; $intIndex -gt -1; $intIndex--) 
	{$listItems.Delete($intIndex)}

$inputCSV | % {
	$newItem = $null
	$newItem = $list.Items.Add()
	$newItem["Title"] = $_.Title
	$newItem["Work Item ID"] = $_.ID
	$newItem["Requester Username"] = $_.Requester
	$newItem["Age (in days)"] = $_.DaysOld
	$newItem["Request Type"] = $_.Area
	$newItem["Urgency"] = $_.Urgency
	$newItem["Priority"] = $_.Priority
	$newItem["Score"] = $_.Weight
	$newItem["Current Status"] = $_.Status
	If($_.ExpectedDeliveryDate -ne $null -and $_.ExpectedDeliveryDate -ne "") {
		$newItem["Expected Delivery Date"] = $_.ExpectedDeliveryDate
	}
	$newItem.Update()
}

