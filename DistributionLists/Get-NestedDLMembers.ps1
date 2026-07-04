<#
.SYNOPSIS
    Recursive Nested Distribution List Membership Auditor.
.DESCRIPTION
    An enterprise administration utility that recursively traverses nested 
    Distribution Lists (DLs) in Exchange Online / Exchange Hybrid to extract 
    all unique end-user members. Outputs metadata (Name, SamAccountName, ObjectClass)
    to a centralized report.
.PARAMETER group
    The primary identity or SMTP address of the parent Distribution List.
.EXAMPLE
    .\Get-NestedDLMembers.ps1
#>

# Initialize global array list to capture nested results across recursive scopes
$global:MembersList = New-Object System.Collections.ArrayList

function Get-MembershipDetails {
    <#
    .SYNOPSIS
        Recursive function to audit group members and drill down into nested groups.
    #>
    param (
        [string]$group
    ) 
    
    try {
        # Fetching group members with an unlimited result size for large enterprises
        $searchGroup = Get-DistributionGroupMember -Identity $group -ResultSize Unlimited
        
        foreach ($member in $searchGroup) {
            # Recursively check if the member is another group
            if ($member.RecipientTypeDetails -match "Group" -and $member.DisplayName -ne "") {
                # Drill down into the child group
                Get-MembershipDetails -group $member.DisplayName
            }           
            else {
                # Append individual user objects to the report payload
                if ($member.DisplayName -ne "") {
                    $global:MembersList.Add([PSCustomObject]@{
                        'Name'           = $member.DisplayName
                        'SamAccountName' = $member.SamAccountName
                        'ObjectClass'    = $member.ObjectClass
                    }) > $null
                }
            }
        }
    } catch {
        Write-Error "Failed to retrieve members for group: $group. Error: $($_.Exception.Message)"
    }
}

# Prompt operator for input dynamically
Write-Host "`n###### Nested Distribution List Auditor ######" -ForegroundColor Green
$TargetDL = Read-Host "Enter the target Distribution List Name or SMTP Address"

if (-not [string]::IsNullOrEmpty($TargetDL)) {
    Write-Host "Auditing nested structure for '$TargetDL'..." -ForegroundColor Yellow
    
    # Execute the recursive function
    Get-MembershipDetails -group $TargetDL
    
    # Generate environment-agnostic output path on user's desktop
    $OutputPath = "$env:USERPROFILE\Desktop\NestedGroupMembers_Export.csv"
    
    # Export results to CSV
    if ($global:MembersList.Count -gt 0) {
        $global:MembersList | Export-Csv -Path $OutputPath -NoTypeInformation
        Write-Host "Successfully exported $($global:MembersList.Count) unique members to: $OutputPath" -ForegroundColor Green
    } else {
        Write-Host "No members discovered or access denied to group objects." -ForegroundColor Yellow
    }
} else {
    Write-Host "No input provided. Operation canceled." -ForegroundColor Red
}
