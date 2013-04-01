Dell-BiosUpdates.ps1
johnpuskar@gmail.com
windowsmasher.wordpress.com

This script is supposed to run Dell BIOS updates from a task sequence in a managable way.

= Preparing for a new model or new updates =
 1) Use powershell to find the 'model' of your pc with the following command: (gwmi win32_computersystem).model .
 2) Create a folder with the same name as the PC's model.
 3) Drop the BIOS update files in the model's folder.

= Multiple Update Steps =
If your system requires multiple update steps, simply place multiple files in the model's folder. The script will select the next-highest from the system's current running bios verion, and apply that update only. For multiple updates, use multiple runs of the script with a reboot between each run.

= Usage =
powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -NoProfile -WindowStyle Hidden -File .\Dell-BiosUpdates.ps1 [BiosPassword]

= Known Issues =
The script will only work on devices where the BIOS update file does ends in A##.exe (ex: A01.exe). Also, most models around or before the Optiplex 745 will not work with this script.