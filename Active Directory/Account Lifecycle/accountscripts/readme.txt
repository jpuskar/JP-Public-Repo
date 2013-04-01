== Account Lifecycle Scripts ==
These scripts are designed to create, maintain, and delete accounts. It's unlikely that you will be able to use these scripts as-is, but feel free to use them as a template. Scanning through the function names will likely help any account lifecycle programming efforts.

=== Create-Accounts ===
This script uses the following workflow:
 1. Accept a list of accounts via GUI Input, XLSX, CSV, an Active Directory user account, or an Active Directory group.
 2. If the account does not exist, validate the input information then create the account.
 3. Perform various health checks against the account such as:
  * File server share existance, share permissions, and NTFS permissions.
  * Roaming profile location and permissions.
  * Home folder location on various file systems.

There is a lot of business logic built in. Much of it is configurable in the Create-Accounts-settings.ps1 file, which is dot-sourced into the script when run.


=== Group Utils ===
This script accepts an active directory group, and performs the following functions:
 1. Creates two groups: ACL_GroupNameShare_AllowRead and ACL_GroupNameShare_AllowWrite.
 2. Creates a share on a file server and assigns Share and NTFS permissions.
 3. Verifies that the group CN is properly set into a mapping script.

There is a lot of business logic built in. Much of it is configurable in the Create-Accounts-settings.ps1 file, which is dot-sourced into the script when run.


=== Archive Users ===
This script accepts a list of users, and performs the following functions:
 1. Exports an LDAP record of the account to a file share, then verifies the LDAP record against Active Directory.
 2. Zip's the user's home drive and profile data.
 3. Verifies the zip file infomation against a file and directory listing of the home drive and profile.
 4. Deletes the home drive and profile.
 5. Deletes the account.

Much of the process is configurable in the Archive-Users-Settings.ps1 script.


