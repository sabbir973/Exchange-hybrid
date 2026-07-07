# This script manages mailbox Legal Holds and performs mailbox dumpster cleaning tasks for ExchangeOnline mailboxes.

# Function to Connect with a service account with proper privileges
function Connect-Services {
    try {
        Write-Host "Disconnecting active Exchange sessions..." -ForegroundColor Cyan
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        
        Write-Host "Connecting to Exchange Online and Compliance Services..." -ForegroundColor Cyan
        # Modern Connect-ExchangeOnline natively bridges both Exchange and Compliance environments
        Connect-ExchangeOnline
    } catch {
        Write-Host "Failed to connect to services. Check Azure PIM for Exchange Online and VPN/Network paths. Error: $_" -ForegroundColor Red
    }
}

$global:output = @()
$global:foundEmails = @()

$script:EmailSent = $true
$script:dtcmRetentionPolicySet = $true
$script:RecoverableItemsToZeroPolicySet = $true
$script:RecoverableItemsTo14DaysPolicySet = $true
$script:lhtcRetentionPolicySet = $true

# Function to handle common errors and log them
function Get-Error {
    param (
        [string]$errorMessage
    )

    $errorlogPath = "C:\Users\wjv9zrh\Desktop\Scripts\LegalHoldUser\LegalHoldScriptError.log"
    Write-Host "Error: $errorMessage" -ForegroundColor Red

    # Ensure the directory exists before logging
    $logDirectory = Split-Path $errorlogPath
    if (-not (Test-Path $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    $errorLogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $errorMessage"
    Add-Content -Path $errorlogPath -Value $errorLogEntry

    throw $errorMessage
}

# Function to get user from Active Directory and Exchange Online
function Get-UserStatus {
    try {
        $inputUsers = Read-Host "Please enter the user email or adid (comma-separated)"
        $users = $inputUsers -split ',' | ForEach-Object { $_.Trim() }

        foreach ($u in $users) {
            $mailbox = Get-Mailbox -Identity $u -ErrorAction SilentlyContinue

            if ($mailbox) {
                $employeeNumber = $mailbox.UserPrincipalName
                $adUser = Get-ADUser -Filter {UserPrincipalName -eq $employeeNumber} -Properties GivenName, Surname, EmailAddress, EmployeeNumber -Server "UPS.com:3268" -ErrorAction SilentlyContinue

                if ($adUser) {
                    $MailboxFolderStats = Get-MailboxFolderStatistics -Identity $u -FolderScope RecoverableItems |
                        Where-Object { $_.FolderPath -eq "/Recoverable Items" }
                    
                    # Safely calculate size using native property methods rather than text splitting
                    $dumpsterSizeGB = 0
                    if ($MailboxFolderStats -and $MailboxFolderStats.FolderAndSubfolderSize) {
                        $dumpsterSizeGB = [math]::Round(($MailboxFolderStats.FolderAndSubfolderSize.ToGB()), 2)
                    }

                    $global:output += [PSCustomObject] @{
                        'DisplayName'        = "$($adUser.GivenName) $($adUser.Surname)"
                        'Email'              = $adUser.EmailAddress
                        'EmpNum'             = $adUser.EmployeeNumber
                        'Dumpster Size (GB)' = $dumpsterSizeGB
                    }
                    $global:foundEmails += $adUser.EmailAddress 
                }
            } else {
                Write-Host "Mailbox not found for: $u" -ForegroundColor Yellow
            }
        }
    } catch {
        Get-Error "Error in Get-UserStatus function. $_"
    }
}

# Function to check holds and provide steps for cleaning mailbox
function Get-InPlaceholdsForUsers {
    try {
        Write-Host "`nChecking User Mailbox Holds:" -BackgroundColor DarkGreen -ForegroundColor White
    
        foreach ($user in $global:foundEmails) {
            $legalHoldUser = Get-Mailbox -Identity $user -ErrorAction SilentlyContinue
            
            if ($legalHoldUser.InPlaceHolds) {
                Write-Host "`nUser $user on Legal Hold: $($legalHoldUser.InPlaceHolds)" -ForegroundColor Yellow
                
                if ($legalHoldUser.InPlaceHolds -match "^mbx") {
                    Set-RetentionCompliancePolicy -Identity "Legal Hold Teams Chat" -RemoveTeamsChatLocation $legalHoldUser.UserPrincipalName
                    Write-Host "Removed the UC Retention policy 'Legal Hold Teams Chat' for user $user"
                    Write-Host "Follow option 2 in the main menu to continue."
                } 
                if ($legalHoldUser.InPlaceHolds -match "^Unih") {
                    Write-Host "Send an email to the eDiscovery team and follow option 2 in the main menu to continue."
                }
            } else {
                Write-Host "`nUser $user has no active InPlaceHolds." -ForegroundColor Green
            }
        }
    } catch {
        Get-Error "Error in Get-InPlaceholdsForUsers function. $_ "
    }
}

# Function to send email reports
function Send-EmailToeDiscoveryTeam {
    try {
        if ($global:output.Count -eq 0) {
            Write-Host "No data collected to send via email." -ForegroundColor Yellow
            return
        }

        $htmlBody = $global:output | 
            ConvertTo-Html -As Table -PreContent "Please approve. Rick/Rob, once approved please remove the holds.<br></br>" -PostContent "<br>Below IDs completed</br>"
    
        $smtpServer     = "smtpapps.us.ups.com"
        $Sender         = "wjv9zrh@ups.com"
        $recipient      = @("wjv9zrh@ups.com")
        $messageSubject = "Dumpster Report"
        $messageBody    = "$htmlBody"

        if ($script:EmailSent) {
            Send-MailMessage -SmtpServer $smtpServer -From $Sender -To $recipient -Subject $messageSubject -BodyAsHtml -Body $messageBody -UseSsl -ErrorAction Stop
            Write-Host "`nEmail sent successfully." -ForegroundColor Green
            $script:EmailSent = $false
        }
        Write-Host "`nActive User Emails: $($global:foundEmails -join ', ')" -ForegroundColor DarkCyan
    } catch {
        Get-Error "Error in Send-EmailToeDiscoveryTeam function. $_"
    }
}

# Function to set Recoverable Items to Zero days for users
function Set-RecoverableItemsToZero {
    try {
        Write-Host "`nSet Recoverable Items setting to Zero:" -BackgroundColor DarkGreen -ForegroundColor White
    
        foreach ($user in $global:foundEmails) {
            if ($script:RecoverableItemsToZeroPolicySet) {
                Set-Mailbox -Identity $user -RetainDeletedItemsFor 0 -SingleItemRecoveryEnabled $False
                Write-Host "Disabled Single Item Recovery and set retention to 0 days for $user" -ForegroundColor Yellow
            }
        }
        $script:RecoverableItemsToZeroPolicySet = $false
    } catch {
        Get-Error "Error in Set-RecoverableItemsToZero function. $_"
    }
}

# Function to Add exception to Retention Policy
function Add-ExceptionToDTCMRetentionPolicy {
    Write-Host "`nSet Retention Policy Exceptions:" -BackgroundColor DarkGreen -ForegroundColor White
    try {
        foreach ($user in $global:foundEmails) {
            $legalHoldUser = Get-Mailbox -Identity $user -ErrorAction SilentlyContinue
            $RetentionPolicy = "Delete Private Teams Channel messages after 2 years"
            
            if (-not ($legalHoldUser.InPlaceHolds) -and $script:dtcmRetentionPolicySet) {
                Write-Host "Adding exception to '$RetentionPolicy' Retention Policy for user $user."
                Set-AppRetentionCompliancePolicy -Identity $RetentionPolicy -AddExchangeLocationException $user
            }
        }
        $script:dtcmRetentionPolicySet = $false
    } catch {
        Get-Error "Error in Add-ExceptionToDTCMRetentionPolicy function. $_"
    }
}

# Function to start mailbox dumpster cleanup
function start-MailboxDumpsterCleanup {
    try {
        foreach ($user in $global:foundEmails) {    
            $mailbox = Get-Mailbox -Identity $user -ErrorAction SilentlyContinue
        
            if ($mailbox.DelayHoldApplied -or $mailbox.DelayReleaseHoldApplied) {
                while ($true) {
                    if ($mailbox.DelayHoldApplied) {
                        Start-Sleep -Seconds 1
                        Set-Mailbox -Identity $user -RemoveDelayHoldApplied
                        Write-Host "DelayHoldApplied removed for $user"
                    }
                    if ($mailbox.DelayReleaseHoldApplied) {
                        Start-Sleep -Seconds 1
                        Set-Mailbox -Identity $user -RemoveDelayReleaseHoldApplied
                        Write-Host "DelayReleaseHoldApplied removed for $user"
                    }
                    
                    Write-Output "Sleeping for 2 minutes before performing mailbox cleanup..."
                    Start-Sleep -Seconds 120
                    
                    Write-Host "Running Managed Folder Assistant on $user" -ForegroundColor Yellow
                    Start-ManagedFolderAssistant -Identity $user
                    
                    $mailbox = Get-Mailbox -Identity $user -ErrorAction SilentlyContinue
                    if (-not ($mailbox.DelayHoldApplied -or $mailbox.DelayReleaseHoldApplied)) {
                        break
                    }
                }
            } else {
                Write-Host "No DelayHold changes needed for $user. Running Managed Folder Assistant..."
                Start-ManagedFolderAssistant -Identity $user
            }
        }
    } catch {
        Get-Error "Error in start-MailboxDumpsterCleanup function. $_"
    }
}

# Function to Set Recoverable Items to 14 days for users
function Set-RecoverableItemsTo14days {
    try {
        Write-Host "`nReset Recoverable Items setting to 14 Days:" -BackgroundColor DarkGreen -ForegroundColor White
        foreach ($user in $global:foundEmails) {
            if ($script:RecoverableItemsTo14DaysPolicySet) {
                Write-Host "Set Recoverable Items to 14 days and enabled Single Item Recovery for user $user."
                Set-Mailbox -Identity $user -RetainDeletedItemsFor 14 -SingleItemRecoveryEnabled $True
            }
        }
        $script:RecoverableItemsTo14DaysPolicySet = $false
    } catch {
        Get-Error "Error in Set-RecoverableItemsTo14days function. $_"
    }
}

# Function to Add users to Legal Hold Teams Chat (lhtc) policy
function Add-UsersToLHTCRetentionPolicy {
    try {
        Write-Host "`nAdding Users to Retention Policy:" -BackgroundColor DarkGreen -ForegroundColor White
    
        foreach ($user in $global:foundEmails) { 
            if ($script:lhtcRetentionPolicySet) {
                Set-RetentionCompliancePolicy -Identity "Legal Hold Teams Chat" -AddTeamsChatLocation $user
                Write-Host "Added user $user to Legal Hold Teams Chat policy."
            }
        }
        $script:lhtcRetentionPolicySet = $false
    } catch {
        Get-Error "Error in Add-UsersToLHTCRetentionPolicy function. $_"
    }
} 

# Function to Get folder statistics for users
function Get-MailboxFolderStatices {
    try {
        $folderStatisticsOutput = @()

        foreach ($user in $global:foundEmails) {
            $userMailbox = Get-Mailbox -Identity $user

            $newMailboxFolderStats = Get-MailboxFolderStatistics -Identity $user -FolderScope RecoverableItems |
                Where-Object { $_.FolderPath -eq "/Recoverable Items" }

            $newDumpsterSizeGB = 0
            if ($newMailboxFolderStats -and $newMailboxFolderStats.FolderAndSubfolderSize) {
                $newDumpsterSizeGB = [math]::Round(($newMailboxFolderStats.FolderAndSubfolderSize.ToGB()), 2)
            }
            
            $folderStatisticsOutput += [PSCustomObject] @{
                'Name'               = $userMailbox.Name
                'Dumpster Size (GB)' = $newDumpsterSizeGB
            }
        }
        # Display the output immediately
        $folderStatisticsOutput | Out-Host
    } catch {
        Get-Error "Error in Get-MailboxFolderStatices function. $_"
    }
}

# Function to display the interactive menu
function Show-Menu {
    param (
        [string]$Title = "###### UPS Legal Hold Mailbox Cleanup ######"
    )
    Clear-Host
    Write-Host -ForegroundColor Yellow "=========== $Title ==========="
    Write-Host "Press '1' Verify User & Check Legal Hold Status."
    Write-Host "Press '2' Clean Dumpster"
    Write-Host "Press 'Q' To Quit." -ForegroundColor Yellow
}

# Main menu loop
try {
    # Check dependencies baseline
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Warning "ActiveDirectory Module is missing. Please install RSAT."
    }
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Host "Installing ExchangeOnlineManagement Module..." -ForegroundColor Cyan
        Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber -Scope CurrentUser
    }
    
    Import-Module -Name ActiveDirectory -ErrorAction SilentlyContinue
    Import-Module -Name ExchangeOnlineManagement -ErrorAction SilentlyContinue

    Connect-Services # Connect at the beginning of script initialization

    do {
        Show-Menu
        $UserInput = (Read-Host "`nPlease make a selection").ToLower().Trim()
        switch ($UserInput) {
            "1" {
                Clear-Host
                Write-Host -ForegroundColor Green "You chose option #1"
                $global:output = @()
                $global:foundEmails = @()
                Get-UserStatus
                Get-InPlaceholdsForUsers
                Send-EmailToeDiscoveryTeam
            } 
            "2" {
                if ($global:foundEmails.Count -eq 0) {
                    Write-Host "No targeted users mapped yet. Please run option 1 first." -ForegroundColor Red
                } else {
                    Clear-Host
                    Write-Host -ForegroundColor Green "You chose option #2"
                    Set-RecoverableItemsToZero
                    Add-ExceptionToDTCMRetentionPolicy
                    
                    Write-Host "`nSleeping for 5 minutes..."
                    Start-Sleep -Seconds 300
                    
                    Write-Host "`nStarting Mailbox Dumpster Cleanup:" -BackgroundColor DarkGreen -ForegroundColor White
                    start-MailboxDumpsterCleanup
                    
                    Write-Host "`nSleeping for 1 hour..."
                    Start-Sleep -Seconds 3600
                    start-MailboxDumpsterCleanup
                    
                    Write-Host "`nSleeping for 1 hour..."
                    Start-Sleep -Seconds 3600
                    start-MailboxDumpsterCleanup
                    
                    Write-Host "`nSleeping for 3 hours..."
                    Start-Sleep -Seconds 10800
                    Set-RecoverableItemsTo14days
                    Add-UsersToLHTCRetentionPolicy
                    Get-MailboxFolderStatices
                }
            } 
            "q" {
                return
            }
        }
        if ($UserInput -ne "q") {
            pause
        }
    } until ($UserInput -eq "q")

} catch {
    Get-Error "Error in the main script loop. $_"
}
