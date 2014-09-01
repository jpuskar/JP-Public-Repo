
$inputWindow = New-Grid -Rows 4 -Columns Auto,* -Name ConvertWindow -Show {
	New-Label "Source SR ID:" -Row 1
	New-TextBox -Name SRIdInput -TextWrapping NoWrap -MaxLines 1 -Row 1 -Column 1
	New-separator -Row 2 -Column 0
	New-separator -Row 2 -Column 1
	#New-Label ""
	New-Label "test" -Row 3
	New-TextBox -Name SRIdInput2 -TextWrapping NoWrap -MaxLines 1 -Row 3 -Column 1
}