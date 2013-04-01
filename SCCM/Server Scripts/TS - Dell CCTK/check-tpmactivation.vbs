'if argument 'warn', set bFailIfDeactivated = True
'if argument 'fail', set bFailIfDeactivated = True
Dim bWarnOnly, bArgOK, mainArg, iExitcode
iExitcode = 0
bArgOK = vbFalse
bWarnOnly = vbFalse
If WScript.Arguments.Count = 1 Then
	mainArg = Wscript.Arguments(0)
	If mainArg = "warnonly" Then
		bArgOK = vbTrue
		bWarnOnly = vbTrue
	End If
ElseIf Wscript.Arguments.Count = 0 Then
	bArgOK = vbTrue
	bWarnOnly = vbFalse
Else
	bArgOK = vbFalse
End If

Dim msg, cmd, text, objShell, strPath, action
If bArgOK = vbTrue Then
	Set objShell = CreateObject("Wscript.Shell")
	
	sExpression = "X:\windows\system32\move-installationprogress.exe"
	objShell.Run sExpression
	
	strPath = Wscript.ScriptFullName
	Set objFSO = CreateObject("Scripting.FileSystemObject")
	Set objFile = objFSO.GetFile(strPath)
	strFolder = objFSO.GetParentFolderName(objFile) 
	'objFile.Close
	
	'ref: http://stackoverflow.com/questions/5690134/running-command-line-silently-with-vbscript-and-getting-output
	cmd = "cmd /c " & strFolder & "\cctk.exe --tpmactivation > " & strFolder & "\tpmout.txt"
	'Wscript.Echo cmd
	action = objShell.Run(cmd, 0, True)
	
	'parse result
	Set objFile = objFSO.OpenTextFile((strFolder & "\tpmout.txt"), 1)
	text = objFile.ReadAll
	objFile.Close
	
	'if 'deactivated' then act
	If InStr(text,"deactivated") Then
		If bWarnOnly = True Then
			msg = "Warning! This system's TPM is deactivated. The task sequence will now attempt to enable the TPM then reboot. If this attempt fails, the task sequence will fail. I recommend entering the BIOS after clicking OK and enabling the TPM manually."
			msgbox msg
			iExitcode = 0
		Else
			msg = "Warning! This task sequence is failing because the TPM is deactivated and the task sequence was not able to enable it manually."
			msgbox msg
			iExitcode = 1
		End If
	End If
Else
	msg = "Arguments invalid."
	iExitcode = 1
End If

Wscript.Quit iExitcode