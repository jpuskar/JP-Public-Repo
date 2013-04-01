'Ask-Questions.vbs
Dim sExpression
Set oShell = WScript.CreateObject ("WScript.shell")
sExpression = "move-installationprogress.exe"
oShell.Run sExpression

q1 = InputBox("This task sequence will -ERASE- all linux partitions and those encrypted with anything other than bitlocker. Type ""erase-other-drives"" to continue, or anything else to quit.","Question 1")
intCompare = StrComp(q1, "erase-other-drives", vbTextCompare)
If intCompare <> 0  Then
		msgbox "Canceling the task sequence."
		WScript.Quit(200)
	End If

msgbox "Task sequence is continuing with the C: backup and format when you click OK. Power off the computer to cancel."