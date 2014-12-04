[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint")
Add-PSSnapin Microsoft.SharePoint.PowerShell
$importFile = $args[0]

$logfile = "C:\scripts\comsol-status.log"

If((Test-Path $importFile) -ne $true) {
	$msg = "Could not find file $importFile"
	$msg > $logFile
}
Else
	{
		$msg = "Opening """ + $importFile + """ ."
		$msg > $logFile
	}

$webListPage = $null
$webListPage = "https://sharepoint1.osuesl.net/sites/esl-it/Lists/Comsol 44 License Status Page/AllItems.aspx"

##ref: http://techchucker.wordpress.com/2013/02/21/outputsplist/
##ref: http://markimarta.com/sharepoint/delete-all-items-in-sharepoint-list-using-powershell/

#Region SP Output File Variables
$inputCSV = Import-CSV $importFile

$webURL = "https://sharepoint1.osuesl.net/sites/esl-it"
$listName = "Comsol 4.4 License Status Page"

#Get the SPWeb object and save to variable
$listWeb = Get-SPWeb $webURL

#Get the SPList object to retrieve the list
$list = $listWeb.Lists[$listName]
#endRegion

#Region Web Application Variable
$Siteurl = "https://sharepoint1.osuesl.net/sites/esl-it"
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
	$newItem["Group Name"] = $_.GroupName
	$newItem["Feature Name"] = $_.FeatureName
	$newItem["Total Licenses"] = $_."Total Licenses"
	$newItem["Free Licenses"] = $_."Free Licenses"
	$newItem["Current Users"] = $_."Current Users"
	$newItem.Update()
}
