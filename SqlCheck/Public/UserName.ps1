Function Get-UserName{
<#
.Synopsis
   Translate user sid into user name
.DESCRIPTION
   The cmdlet translates the user's security identifier to the name
.EXAMPLE
   Get-UserName -UserSID 'S-1-5-21-Some-Number-here-0000'
.INPUTS
   A User Security Identifier (SID)
.OUTPUTS
   User Name
#>    
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$UserSID
    )
    Process{
        $objSID = New-Object System.Security.Principal.SecurityIdentifier($UserSID)
        $objUser = $objSID.Translate( [System.Security.Principal.NTAccount])
        $objUser.Value
    }
}

Function Get-UserSID{
<#
.Synopsis
   Translate user name to user sid
.DESCRIPTION
   The cmdlet translates the user's name to the security identifier
.EXAMPLE
   Get-UserName -Username 'Naw.Awn'
.INPUTS
   User Name
.OUTPUTS
   A User Security Identifier (SID)
#> 
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$UserName
    )
    Process{ 
        $objUser = New-Object System.Security.Principal.NTAccount($UserName)
        $objSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
        $objSID.Value
    }
}