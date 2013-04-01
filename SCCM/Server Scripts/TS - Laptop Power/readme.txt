Dell-BiosUpdates.ps1
johnpuskar@gmail.com
windowsmasher.wordpress.com

This script creates a 2 popups in a WinPE Task Sequence.
 1) Connect Power Adapter
 2) Wait for battery to be 60% charged

For each popup, once the condition is satisfied the task sequence continues. Desktop computers should skip the popups entirely.

To use the script:
 1) Download and install AutoIt.
 2) Compile a 32 and 64 bit version of the program.
 3) Add the compiled EXE files to the following respective folders on your SCCM site server:
     * C:\Program Files\Microsoft Configuration Manager\OSD\Extras\Power32
     * C:\Program Files\Microsoft Configuration Manager\OSD\Extras\Power64
 4) Modify the following file on your site server: C:\Program Files\Microsoft Configuration Manager\bin\X64\osdinjection.xml. Add the following lines in the respective sections:

--to the i386\SCCM section:
<File name="waitforbattery.exe">
	<LocaleNeeded>false</LocaleNeeded>
	<Source>extra\power32</Source>
	<Destination>windows\system32</Destination>
</File>

--to the x64\SCCM section:
<File name="waitforbattery.exe">
	<LocaleNeeded>false</LocaleNeeded>
	<Source>extra\power64</Source>
	<Destination>windows\system32</Destination>
</File>

 5) Update distribution points for your boot images.
 6) Add a 'run command line' task sequence action with the following command line:
X:\windows\system32\waitforbattery.exe

Then you're all set!