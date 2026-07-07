<#
.SYNOPSIS
    Queries Active Directory to check account lifecycle status via Email or Account ID.
.DESCRIPTION
    Accepts a comma-separated list of user identifiers from a host prompt, filters 
    them against the specified Global Catalog, and outputs a structured status table.
.NOTES
    Adjust the configuration variables below to match your organization's environment.
#>

# --- CONFIGURATION (Customize for your environment) ---
$GlobalCatalogServer = "yourdomain.com:3268"  # Your internal Active Directory Global Catalog
# ------------------------------------------------------

$userInput = Read-Host "Please enter the user email or Account ID (comma-separated)"
if ([string]::IsNullOrWhiteSpace($userInput)) { 
    Write-Warning "No input provided. Exiting."
    exit 
}

# Split and clean the comma-separated identities
$userIdentities = $userInput -split ',' | ForEach-Object { $_.Trim() }
$output = @()

foreach ($identity in $userIdentities) {
    # Dynamically determine if the input is an email or an account ID
    if ($identity -like "*@*") {
        $filter = "EmailAddress -eq '$identity'"
    } else {
        $filter = "SamAccountName -eq '$identity'"
    }

    $validUser = Get-ADUser -Filter $filter -Server $GlobalCatalogServer -Properties EmployeeNumber, EmailAddress, GivenName, Surname, Enabled -ErrorAction SilentlyContinue
       
    if ($validUser) {
        # Establish status string based on Active Directory account state
        $status = if ($validUser.Enabled) { 'Active' } else { 'Disabled' }
        $fullName = "{0} {1}" -f $validUser.GivenName, $validUser.Surname

        $output += [PSCustomObject]@{
            'Status'         = $status
            'Name'           = $fullName.Trim()
            'Identifier'     = $identity
            'EmailAddress'   = $validUser.EmailAddress
            'EmployeeNumber' = $validUser.EmployeeNumber
        }
    } else {
        $output += [PSCustomObject]@{
            'Status'         = 'NotFound/Inactive'
            'Name'           = ''
            'Identifier'     = $identity
            'EmailAddress'   = ''
            'EmployeeNumber' = ''
        }
    }
}

# Render output structured to the host console width
$output | Format-Table -AutoSize
