#######
## Add system to domain and rename, name is based on VM name in Hyper-V
#######

$domainName = "vdi.network"
$password = get-content C:\users\administrator\Documents\cred.txt | convertto-securestring
$credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist "administrator@vdi.network",$password
$oldname = hostname

$vmName = (Get-ItemProperty –path “HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters”).VirtualMachineName

Add-Computer -DomainName $domainName -Credential $credentials
start-sleep -s 30
Rename-Computer -NewName "$vmName"

#######
##Create OU's, remote groups and move system into company OU
#######

$hostname = (Get-ItemProperty –path “HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters”).VirtualMachineName

invoke-command admaster1.vdi.network -ScriptBlock {
    param($hostname)
     NEW-ADOrganizationalUnit “$hostname” –path “OU=Manulife,OU=Goldmine Subscriptions,OU=Hosted Companies,DC=VDI,DC=NETWORK” } -credential $credentials -ArgumentList $hostname

invoke-command admaster1.vdi.network -ScriptBlock {
    param($hostname)
     NEW-ADgroup “$hostname-remote” -groupscope Global –path “OU=$hostname,OU=Manulife,OU=Goldmine Subscriptions,OU=Hosted Companies,DC=VDI,DC=NETWORK” } -credential $credentials -ArgumentList $hostname

invoke-command admaster1.vdi.network -ScriptBlock {
    param($hostname)
    get-adcomputer $hostname | Move-ADObject -TargetPath “OU=$hostname,OU=Manulife,OU=Goldmine Subscriptions,OU=Hosted Companies,DC=VDI,DC=NETWORK” } -credential $credentials -ArgumentList $hostname


#######
##Provision Storage Drive and Map to C:\Company\
#######

mkdir C:\Company\
$commands=@(
'select disk 1'
'online disk NOERR'
'select disk 1' 
'convert gpt NOERR'
'attributes disk clear readonly NOERR'
'create partition primary NOERR'
'format quick fs=ntfs label="Company Files"'
'assign mount=C:\Company\'
)
$commands | diskpart

#######
##Create Volume Shadow Copies and schedule
#######

$diskname = "C:\"
$VolumeWmi = gwmi Win32_Volume -Namespace root/cimv2 | ?{ $_.Name -eq $diskname }
$DeviceID = $VolumeWmi.DeviceID.ToUpper().Replace("\\?\VOLUME", "").Replace("\","")
$TaskName = "ShadowCopyVolume" + $DeviceID
$TaskFor = "\\?\Volume" + $DeviceID + "\"
$Task = "C:\Windows\system32\vssadmin.exe"
$Argument = "Create Shadow /AutoRetry=15 /For=$TaskFor"
$WorkingDir = "%systemroot%\system32"

$ScheduledAction = New-ScheduledTaskAction –Execute $Task -WorkingDirectory $WorkingDir -Argument $Argument
$ScheduledTrigger = @()
$ScheduledTrigger += New-ScheduledTaskTrigger -Daily -At 10:00
$ScheduledTrigger += New-ScheduledTaskTrigger -Daily -At 15:00
$ScheduledSettings = New-ScheduledTaskSettingsSet -Compatibility V1 -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Days 3) -Priority 5
$ScheduledTask = New-ScheduledTask -Action $ScheduledAction -Trigger $ScheduledTrigger -Settings $ScheduledSettings
Register-ScheduledTask $TaskName -InputObject $ScheduledTask -User "NT AUTHORITY\SYSTEM"

vssadmin.exe Resize ShadowStorage /for=C: /On=C: /MaxSize=25%

$diskname = "C:\Company\"
$VolumeWmi = gwmi Win32_Volume -Namespace root/cimv2 | ?{ $_.Name -eq $diskname }
$DeviceID = $VolumeWmi.DeviceID.ToUpper().Replace("\\?\VOLUME", "").Replace("\","")
$TaskName = "ShadowCopyVolume" + $DeviceID
$TaskFor = "\\?\Volume" + $DeviceID + "\"
$Task = "C:\Windows\system32\vssadmin.exe"
$Argument = "Create Shadow /AutoRetry=15 /For=$TaskFor"
$WorkingDir = "%systemroot%\system32"

$ScheduledAction = New-ScheduledTaskAction –Execute $Task -WorkingDirectory $WorkingDir -Argument $Argument
$ScheduledTrigger = @()
$ScheduledTrigger += New-ScheduledTaskTrigger -Daily -At 10:00
$ScheduledTrigger += New-ScheduledTaskTrigger -Daily -At 15:00
$ScheduledSettings = New-ScheduledTaskSettingsSet -Compatibility V1 -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Days 3) -Priority 5
$ScheduledTask = New-ScheduledTask -Action $ScheduledAction -Trigger $ScheduledTrigger -Settings $ScheduledSettings
Register-ScheduledTask $TaskName -InputObject $ScheduledTask -User "NT AUTHORITY\SYSTEM"

vssadmin.exe Resize ShadowStorage /for=C:\Company /On=C:\Company /MaxSize=25%


#Variables :)
$PManagers = @("192.168.200.36") 
## ADD YOUR MANAGER(s) in format @("manager1","manager2")
$CommString = @("vdinetworksnms") # ADD YOUR COMM STRING(s) in format @("Community1","Community2")

#Import ServerManger Module
Import-Module ServerManager

Get-WindowsFeature -name SNMP-service | Add-WindowsFeature -IncludeManagementTools | Out-Null


$check = Get-WindowsFeature -Name SNMP-Service

##Verify Windows Services Are Enabled
If ($check.Installed -eq "True")
    {
    Write-Host "Configuring SNMP Services..."
    #Set SNMP Permitted Manager(s) ** WARNING : This will over write current settings **
    reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\PermittedManagers" /v 1 /t REG_SZ /d localhost /f | Out-Null

    #Set SNMP Traps and SNMP Community String(s) - *Read Only*
    Foreach ($String in $CommString)
        {
        reg add ("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\TrapConfiguration\" + $String) /f | Out-Null
        # Set the Default value to be null
        reg delete ("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\TrapConfiguration\" + $String) /ve /f | Out-Null
        reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\ValidCommunities" /v $String /t REG_DWORD /d 4 /f | Out-Null
        $i = 2
        Foreach ($Manager in $PManagers)
            {
            reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\PermittedManagers" /v $i /t REG_SZ /d $manager /f | Out-Null

            reg add ("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\TrapConfiguration\" + $String) /v $i /t REG_SZ /d $manager /f | Out-Null
            $i++
            }
        }
    }
Else 
    {

    Write-Host "Error: SNMP Services Not Installed"
}
