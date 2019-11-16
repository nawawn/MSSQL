Function Get-UserName{
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$UserSID
    )
    Process{
        $objSID = New-Object System.Security.Principal.SecurityIdentifier ($UserSID)
        $objUser = $objSID.Translate( [System.Security.Principal.NTAccount])
        $objUser.Value
    }
}

Function Get-UserSID{
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