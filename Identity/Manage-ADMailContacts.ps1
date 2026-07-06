<#
.SYNOPSIS
    Active Directory Contact Object and Mail Coexistence Management Tool.
.DESCRIPTION
    A menu-driven PowerShell utility designed for Exchange Hybrid environments. 
    Automates the bulk collection of external user data, provisions local Active 
    Directory contact objects in a designated OU, waits for directory replication, 
    and mail-enables the objects with external SMTP routing addresses.
.PARAMETER firstName
    The first name of the contact.
.PARAMETER lastName
    The last name of the contact.
.PARAMETER email
    The target external SMTP address for the contact.
.EXAMPLE
    .\Manage-ADHybridContacts.ps1
#>

function Connect-Services {
    <#
    .SYNOPSIS
        Validates and imports required enterprise modules.
    #>
    Set-ADServerSettings -ViewEntireForest $true
    try {
        if (-not(Get-Module ActiveDirectory -ListAvailable) -and (Get-Module ExchangeOnlineManagement -ListAvailable)) {
            Import-Module -Name ActiveDirectory -Force
        }
    } catch {
        throw $_
    }
}

# Initialize required configurations
Connect-Services 

Write-Host "`n###### Create Hybrid Contact Object Utilities ######" -ForegroundColor Green

function Get-UserInfo {
    <#
    .SYNOPSIS
        Interactively collects and validates contact metadata from the operator.
    #>
    param (
        [string]$firstName,
        [string]$lastName,
        [string]$fullName,
        [string]$email,
        [string]$company,
        [string]$title,
        [string]$phoneNumber
    )

    $contacts = @() 
    do {
        $firstName = (Read-Host "First Name").Trim()
        $lastName = (Read-Host "Last Name").Trim()
        $fullName = $firstName + " " + $lastName
        $email = (Read-Host "Email Address").Trim()
        $company = (Read-Host "Company").Trim()
        $title = (Read-Host "Title").Trim()
    
        # Validate phone number format via RegEx loop
        do {
            $phoneNumber = Read-Host "Phone Number (123-456-7890 or leave blank)"
            $phoneNumberPattern = '^\d{3}-\d{3}-\d{4}$'
            if ($phoneNumber -eq "" -or $phoneNumber -match $phoneNumberPattern) {
                break
            } else {
                Write-Host "Invalid phone number format. Please use 123-456-7890." -ForegroundColor Red
            }
        } while ($true)
    
        $contacts += [PSCustomObject]@{
            FirstName   = $firstName
            LastName    = $lastName
            FullName    = $fullName
            Email       = $email
            Company     = $company
            Title       = $title
            PhoneNumber = $phoneNumber
            Date        = Get-Date -Format "MM/dd/yyyy hh:mm:ss tt"
        }
        $more = Read-Host "`nDo you want to add another contact? (Y/N)"
        Write-Host "---------------------------------------------"
    
    } while ($more -eq 'Y' -or $more -eq 'y')
    
    return $contacts
}

function Add-ContactObjectName {
    <#
    .SYNOPSIS
        Provisions the base contact object within Active Directory.
    #>
    param (
        [string]$fullName
    )
    try {
        # Genericized Target OU Path for Public Portfolio Safety
        $TargetOU = "OU=Contacts,OU=HybridObjects,OU=Exchange,DC=yourdomain,DC=com"

        New-ADObject -Name "$fullName" -Type "contact" -Path $TargetOU
        Write-Output "Contact object '$fullName' created successfully."
    } catch {
        if ($_ -match '\*Error: An attempt was made to add an object') {
            Write-Host "Failed to create contact object '$fullName' because this name is already in use." -ForegroundColor Red
        } else {
            Write-Error "Failed to create contact object '$fullName'. Error: $($_.Exception.Message)"
        }
    }
}

function Add-ContactObjectUserInfo {
    <#
    .SYNOPSIS
        Mail-enables the AD contact and maps modern routing attributes.
    #>
    param (
        [string]$firstName,
        [string]$lastName,
        [string]$fullName,
        [string]$email,
        [string]$company,
        [string]$title,
        [string]$phoneNumber
    )
    try {
        # Establish mail coexistence attributes
        Enable-MailContact -Identity $fullName -ExternalEmailAddress $email
        Set-Contact -Identity "$fullName" -FirstName "$firstName" -LastName "$lastName" -Company "$company" -Title "$title" -Phone "$phoneNumber"

        Write-Output "`nMail contact for '$fullName ($email)' enabled successfully."
    } catch {
        Write-Error "Failed to enable mail contact for '$fullName'. Error: $($_.Exception.Message)"
    }
}

function Add-Contact {
    <#
    .SYNOPSIS
        Orchestrates batch processing and accounts for replication delays.
    #>
    $userContacts = Get-UserInfo
    
    # Optional localized transaction logging
    $LogPath = "$env:USERPROFILE\Desktop\ContactObject_Log.csv"
    $userContacts | Export-Csv -Path $LogPath -Append -NoTypeInformation

    # Phase 1: Create base objects in Active Directory
    foreach ($contact in $userContacts) {
        Add-ContactObjectName -fullName $contact.FullName
    }

    # Phase 2: Active Directory Replication Wait Interval
    Write-Output "Waiting 3 minutes to ensure multi-DC replication settles before running Exchange lifecycle cmdlets..."
    Start-Sleep -Seconds 150

    # Phase 3: Apply Exchange attributes and address routing
    foreach ($contact in $userContacts) {
        Add-ContactObjectUserInfo -fullName $contact.FullName -FirstName $contact.FirstName -lastName $contact.LastName -email $contact.Email -company $contact.Company -title $contact.Title -phoneNumber $contact.PhoneNumber
    }
}

function Show-MainMenu {
    Write-Host "`n====================="
    Write-Host "1. Create Contact"
    Write-Host "2. Delete Contact [Placeholder]"
    Write-Host "3. Update Contact [Placeholder]"
    Write-Host "4. Exit"
    Write-Host "====================="
}

# Main execution frame loop
do {
    Show-MainMenu
    $choice = Read-Host "Please select an Option"

    switch ($choice) {
        1 { Add-Contact }
        2 { Write-Host "Delete module pending implementation." -ForegroundColor Yellow }
        3 { Write-Host "Update module pending implementation." -ForegroundColor Yellow }
        4 { break }
        Default { Write-Host "Invalid option, please select again." -ForegroundColor Red }
    }

    $continueMainMenu = Read-Host "Return to Main Menu? (y/n)"
} while ($continueMainMenu -eq 'y' -or $continueMainMenu -eq 'Y')
