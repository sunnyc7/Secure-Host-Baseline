#requires -RunAsAdministrator
#requires -Version 5
Set-StrictMode -Version 5


Function Test-IsDomainJoined() {
    [CmdletBinding()]
    [OutputType([bool])]
    Param()
    #todo: function documentation
    $computer = Get-WmiObject -Class 'Win32_ComputerSystem' | Select-Object PartOfDomain

    return $computer.PartOfDomain
}

Function Test-RegistryValue() {
<#
    .SYNOPSIS  
    Tests if a registry value exists.
   
    .DESCRIPTION
    Tests if a registry value exists in the specified hive at the specified path.
   
    .PARAMETER Hive
    The registry hive to check.
   
    .PARAMETER Path
    The path of the registry key to check, not including the hive.
   
    .PARAMETER Name
    The name of the registry value to check.
     
    .EXAMPLE
    Test-RegistryValue -Hive 'hklm' -Path 'Software\Microsoft\Windows\CurrentVersion' -Name 'ProgramFilesDir'

    .EXAMPLE
    Test-RegistryValue 'hklm' 'Software\Microsoft\Windows\CurrentVersion' 'ProgramFilesDir'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    Param(
        [Parameter(Position=0, Mandatory=$true, HelpMessage='The registry hive to check.')]
        [ValidateNotNullOrEmpty()]
        [string]$Hive,
      
        [Parameter(Position=1, Mandatory=$true, HelpMessage='The path of the registry key, not including the hive.')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
      
        [Parameter(Position=2, Mandatory=$true, HelpMessage='The name of the registry value to check.')]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
        $exists = $false

    try {
        Get-ItemProperty -Path ('{0}:\{1}' -f $Hive,$Path) -ErrorAction stop | Select-Object -ExpandProperty $Name -ErrorAction stop | Out-Null
        $exists = $true
    } catch [System.Management.Automation.PSArgumentException],[System.Management.Automation.ItemNotFoundException],[System.Management.Automation.ActionPreferenceStopException] {
        $exists = $false
    }

    return $exists
}

Function Uninstall-Powershell2() {
    <#
    .SYNOPSIS
    Uninstalls PowerShell 2.0.

    .DESCRIPTION
    Uninstalls PowerShell 2.0 to prevent downgrade to avoid PowerShell script blocking logging introduced in PowerShell 5.0.

    .EXAMPLE
    Uninstall-PowerShell2
    #>
    [CmdletBinding()] 
    [OutputType([void])]
    Param()

    $ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

    Disable-WindowsOptionalFeature -Online -FeatureName 'MicrosoftWindowsPowerShellV2','MicrosoftWindowsPowerShellV2Root' -ErrorAction SilentlyContinue | Out-Null
}

Function Uninstall-SMB1() {
    <#
    .SYNOPSIS
    Uninstalls SMB 1.0.

    .DESCRIPTION
    Uninstalls Server Message Block 1.0 protocol since SMB 1.0 is only required for communicating with Windows XP and Windows Server 2003 both of which are end of life.

    .EXAMPLE
    Uninstall-SMB1
    #>
    [CmdletBinding()] 
    [OutputType([void])]
    Param()

    $ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

    Disable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -NoRestart | Out-Null
}

Function Disable-NetBIOS() {
    <#
    .SYNOPSIS
    Disable NetBIOS.

    .DESCRIPTION
    Disable NetBIOS on all network interfaces regardless of whether the interface is active or not. NetBIOS is suspectible to man-in-the-middle attacks and is not required in a domain.

    .PARAMETER -IncludeStandalone
    Disable NetBIOS on standalone systems. By default only domain joined systems will have NetBIOS disabled.

    .EXAMPLE
    Disable-NetBIOS

    .EXAMPLE
    Disable-NetBIOS -IncludeStandalone
    #>
    [CmdletBinding()]
    [OutputType([void])]
    Param(
        [Parameter(Position=0, Mandatory=$false, HelpMessage='Disable NetBIOS on standalone systems')]
        [switch]$IncludeStandalone    
    )

    # ePO might have issues with disabling NetBIOS: https://kc.mcafee.com/corporate/index?page=content&id=KB76756 and https://kc.mcafee.com/corporate/index?page=content&id=KB56386
    # see also: https://support.microsoft.com/en-us/kb/313314

    if((Test-IsDomainJoined) -or $IncludeStandalone) {
        $hive = 'hklm'
        $keyPath = 'SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
        $valueName = 'NetbiosOptions'
        $previousValueName = 'Previous_NetbiosOptions'

        # https://msdn.microsoft.com/en-us/library/windows/hardware/dn923165(v=vs.85).aspx
        # 0 = Use DHCP server setting, 1 = Enabled, 2 = Disabled
        $disabledValue = 2

        Get-ChildItem -Path ('{0}:\{1}' -f $hive,$keyPath) -Recurse | Where-Object { $_.GetValue($valueName) -ne $disabledValue } | ForEach-Object { 
            $currentValue = $_.GetValue($valueName)

            # create a backup value, if it doesn't exist, so that we can use it to restore the setting to the previous value
            if (-not(Test-RegistryValue -Hive $hive -Path ('{0}\{1}' -f $keyPath,$_.PSChildName) -Name $previousValueName)) {        
                Set-ItemProperty -Path ('{0}:\{1}\{2}' -f $hive,$keyPath,$_.PSChildName) -Name $previousValueName -Value $currentValue
            }

            Set-ItemProperty -Path ('{0}:\{1}\{2}' -f $hive,$keyPath,$_.PSChildName) -Name $valueName -Value $disabledValue 
        }
    }
}

Function Restore-NetBIOS() {
    <#
    .SYNOPSIS
    Restores NetBIOS to the previously saved state.

    .DESCRIPTION
    Restores NetBIOS to the previously saved state on all network interfaces regardless of whether the interface is active or not.

    .PARAMETER -IncludeStandalone
    Restore NetBIOS on standalone systems. By default only domain joined systems will have NetBIOS restored.

    .EXAMPLE
    Restore-NetBIOS

    .EXAMPLE
    Restore-NetBIOS -IncludeStandalone
    #>
    [CmdletBinding()]
    [OutputType([void])]
    Param(
        [Parameter(Position=0, Mandatory=$false, HelpMessage='Restore NetBIOS on standalone systems')]
        [switch]$IncludeStandalone    
    )

    if((Test-IsDomainJoined) -or $IncludeStandalone) {
        $hive = 'hklm'
        $keyPath = 'SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
        $valueName = 'NetbiosOptions'
        $previousValueName = 'Previous_NetbiosOptions'

        Get-ChildItem -Path ('{0}:\{1}' -f $hive,$keyPath) -Recurse | Where-Object { $_.GetValue($previousValueName) -ne $null } | ForEach-Object { 
            $currentValue = $_.GetValue($valueName)
            $previousValue = $_.GetValue($previousValueName)

            # create a backup value, if it doesn't exist, so that we can use it to restore the setting to the previous value
            if ($currentValue-ne  $previousValue) {        
                Set-ItemProperty -Path ('{0}:\{1}\{2}' -f $hive,$keyPath,$_.PSChildName) -Name $valueName -Value $previousValue
            }

            Remove-ItemProperty -Path ('{0}:\{1}\{2}' -f $hive,$keyPath,$_.PSChildName) -Name $previousValueName
        }
    }
}