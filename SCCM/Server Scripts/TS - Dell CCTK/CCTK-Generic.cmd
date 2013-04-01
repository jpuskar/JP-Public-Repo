@ECHO OFF
REM Parse Arguments
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
 
SET ARGV=.%*
CALL :PARSE_ARGV
IF ERRORLEVEL 1 (
  ECHO Cannot parse arguments
  ENDLOCAL
  EXIT /B 1
)

REM ---START MAIN LOOP---
ECHO == Seting BIOS Settings ==
ECHO --Enabling TPM
%~dp0cctk.exe --tpm=on !ARG1! !ARG2!
cscript.exe //nologo %~dp0Show-CCTKErrors.vbs %errorlevel%
IF errorlevel 157 GOTO END

ECHO --Activating TPM
%~dp0cctk.exe --tpmactivation=activate !ARG1! !ARG2!
cscript.exe //nologo %~dp0Show-CCTKErrors.vbs %errorlevel%

ECHO --Attempting to set ATA sata mode
%~dp0cctk.exe --embsataraid=ata !ARG1! !ARG2!
cscript.exe //nologo %~dp0Show-CCTKErrors.vbs %errorlevel%

ECHO --Attempting to set AHCI sata mode
%~dp0cctk.exe --embsataraid=ahci !ARG1! !ARG2!
cscript.exe //nologo %~dp0Show-CCTKErrors.vbs %errorlevel%

ECHO --Attempting to set RAID ON sata mode
%~dp0cctk.exe --embsataraid=raid !ARG1! !ARG2!
cscript.exe //nologo %~dp0Show-CCTKErrors.vbs %errorlevel%

ECHO --Enabling other features
%~dp0cctk.exe -i OSUChem_Universal_CCTK.cctk !ARG1! !ARG2!
cscript.exe //nologo %~dp0Show-CCTKErrors.vbs %errorlevel%

REM ---END MAIN LOOP---
GOTO END



:PARSE_ARGV
REM ref: http://skypher.com/index.php/2010/08/17/batch-command-line-arguments/
  SET PARSE_ARGV_ARG=[]
  SET PARSE_ARGV_END=FALSE
  SET PARSE_ARGV_INSIDE_QUOTES=FALSE
  SET /A ARGC = 0
  SET /A PARSE_ARGV_INDEX=1
  :PARSE_ARGV_LOOP
  CALL :PARSE_ARGV_CHAR !PARSE_ARGV_INDEX! "%%ARGV:~!PARSE_ARGV_INDEX!,1%%"
  IF ERRORLEVEL 1 (
    EXIT /B 1
  )
  IF !PARSE_ARGV_END! == TRUE (
    EXIT /B 0
  )
  SET /A PARSE_ARGV_INDEX=!PARSE_ARGV_INDEX! + 1
  GOTO :PARSE_ARGV_LOOP
 
  :PARSE_ARGV_CHAR
    IF ^%~2 == ^" (
      SET PARSE_ARGV_END=FALSE
      SET PARSE_ARGV_ARG=.%PARSE_ARGV_ARG:~1,-1%%~2.
      IF !PARSE_ARGV_INSIDE_QUOTES! == TRUE (
        SET PARSE_ARGV_INSIDE_QUOTES=FALSE
      ) ELSE (
        SET PARSE_ARGV_INSIDE_QUOTES=TRUE
      )
      EXIT /B 0
    )
    IF %2 == "" (
      IF !PARSE_ARGV_INSIDE_QUOTES! == TRUE (
        EXIT /B 1
      )
      SET PARSE_ARGV_END=TRUE
    ) ELSE IF NOT "%~2!PARSE_ARGV_INSIDE_QUOTES!" == " FALSE" (
      SET PARSE_ARGV_ARG=[%PARSE_ARGV_ARG:~1,-1%%~2]
      EXIT /B 0
    )
    IF NOT !PARSE_ARGV_INDEX! == 1 (
      SET /A ARGC = !ARGC! + 1
      SET ARG!ARGC!=%PARSE_ARGV_ARG:~1,-1%
      IF ^%PARSE_ARGV_ARG:~1,1% == ^" (
        SET ARG!ARGC!_=%PARSE_ARGV_ARG:~2,-2%
        SET ARG!ARGC!Q=%PARSE_ARGV_ARG:~1,-1%
      ) ELSE (
        SET ARG!ARGC!_=%PARSE_ARGV_ARG:~1,-1%
        SET ARG!ARGC!Q="%PARSE_ARGV_ARG:~1,-1%"
      )
      SET PARSE_ARGV_ARG=[]
      SET PARSE_ARGV_INSIDE_QUOTES=FALSE
    )
    EXIT /B 0


:END
ENDLOCAL

EXIT /B %errorlevel%