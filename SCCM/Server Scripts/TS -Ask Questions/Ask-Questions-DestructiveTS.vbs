'Ask-Questions.vbs
Dim sExpression
Set oShell = WScript.CreateObject ("WScript.shell")
sExpression = "move-installationprogress.exe"
oShell.Run sExpression

q1 = InputBox("Are you sure you want to reformat this computer and wipe all data from it? Enter yes to continue. If this machine has data that needs backed up, please restart the PC and run Backup, Reformat, and Install")
intCompare = StrComp(q1, "yes", vbTextCompare)
If intCompare <> 0  Then
	msgbox "This task sequence will wipe the machine. Please restart the task sequence when you are ready to wipe this machine."
	WScript.Quit(100)
End If

msgbox "Task sequence is continuing with the format when you click OK. Power off the computer to cancel."
WScript.Quit(0)