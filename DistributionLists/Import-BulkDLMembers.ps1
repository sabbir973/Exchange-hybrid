<#
.SYNOPSIS
    Bulk adds Active Directory or Exchange Distribution Group members from a CSV file.
.DESCRIPTION
    This script reads a CSV file containing user identifiers (ADID) and adds them 
    to a specified target Active Directory group in a single high-performance operation.
.PARAMETER CsvPath
    The full path to the CSV file containing the user list.
.PARAMETER GroupName
    The Identity (Name, SAMAccountName, DistinguishedName, or GUID) of the target AD group.
.EXAMPLE
    .\Import-BulkGroupMembers.ps1 -CsvPath "D:\list.csv" -GroupName "All-Mahwah-Staff"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Path to the source CSV file.")]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter(Mandatory = $true, HelpMessage = "Target AD / Distribution Group identity.")]
    [string]$GroupName
)

begin {
    Write-Verbose "Initializing bulk group import execution."
}

process {
    try {
        Write-Verbose "Importing data from: $CsvPath"
        # Extract the ADID column properties directly into a clean array
        $UserArray = (Import-Csv -Path $CsvPath).ADID

        if (-not $UserArray) {
            Write-Warning "The specified CSV did not contain any data or is missing the 'ADID' column header."
            return
        }

        Write-Host "Found $($UserArray.Count) target identities to process." -ForegroundColor Cyan
        Write-Host "Adding members to group '$GroupName'..." -ForegroundColor Yellow

        # Execute a high-performance single network block query to the domain controller
        Add-ADGroupMember -Identity $GroupName -Members $UserArray

        Write-Host "Successfully populated group '$GroupName' with all CSV members." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to complete bulk group membership modification. Reason: $_"
    }
}

end {
    Write-Verbose "Script execution completed."
}
