<#
.SYNOPSIS
    Restricts a room mailbox booking policy and appends specified users.
.DESCRIPTION
    Validates a room mailbox target, ensures its 'AllBookInPolicy' configuration 
    is restricted (False), checks whether a collection of provided users exist, 
    and appends them onto the mailbox's BookInPolicy array.
.NOTES
    Designed to be dot-sourced or run safely as a reusable utility cmdlet.
#>

function Add-UsersToRoomMailbox {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$RoomMailboxIdentity, 
        
        [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Enter comma-separated list of emails or Account IDs")]
        [ValidatePattern("^[^,]+(,[^,]+)*$")]
        [string]$AdditionalUsers 
    )

    try {
        # Validate RoomMailboxIdentity exists
        Write-Verbose "Checking room mailbox context: $RoomMailboxIdentity"
        $calendarProcessing = Get-CalendarProcessing -Identity $RoomMailboxIdentity -ErrorAction Stop

        # Split and clean input identities
        $usersArray = $AdditionalUsers -split ',' | ForEach-Object { $_.Trim() }
        $validUsers = @()

        # Validate that each user identity exists in the directory
        foreach ($userID in $usersArray) {
            $recipient = Get-Recipient -Identity $userID -ErrorAction SilentlyContinue
            if (-not $recipient) {
                Write-Error "Target recipient identity '$userID' does not exist in the environment. Aborting operation."
                return
            }
            # Gather unique identifier value
            $validUsers += $recipient.PrimarySmtpAddress
        }

        # Restrict the default policy if it hasn't been already
        if ($calendarProcessing.AllBookInPolicy -eq $true) {
            Write-Output "Restricting the mailbox by changing AllBookInPolicy to False."
            Set-CalendarProcessing -Identity $RoomMailboxIdentity -AllBookInPolicy $false
        } else {
            Write-Output "AllBookInPolicy is already enforced as False."
        }

        # Retrieve the existing array of allowed booking identities
        $existingBookingPolicy = @($calendarProcessing.BookInPolicy)

        # Merge new users cleanly without creating duplicate array items
        foreach ($userAddress in $validUsers) {
            if ($existingBookingPolicy -notcontains $userAddress) {
                $existingBookingPolicy += $userAddress
                Write-Host "Appending user '$userAddress' to the room booking policy." -ForegroundColor Cyan
            } else {
                Write-Host "User '$userAddress' is already explicitly defined in the booking policy." -ForegroundColor Yellow
            }
        }

        # Commit the updated collection block back to the calendar instance
        Set-CalendarProcessing -Identity $RoomMailboxIdentity -BookInPolicy $existingBookingPolicy  
        Write-Output "Successfully updated Room Mailbox booking policies."

    } catch {
        Write-Error "An unhandled execution failure occurred: $_"
    }
}
