<#
.SYNOPSIS
    Performs batch DNS resolution lookups using nslookup and exports results to a CSV.
.DESCRIPTION
    Accepts a comma-separated list of domains from a host prompt, executes standard nslookup 
    queries against them sequentially with a built-in delay, parses the output arrays, 
    and saves a clean report directly to the user's desktop.
.NOTES
    Outputs directly to the active user's desktop environment without using hardcoded paths.
#>

# --- CONFIGURATION (Customize for your environment) ---
$OutputCSVPath = "$env:USERPROFILE\Desktop\nslookupResults.csv"
$DelaySeconds  = 3
# ------------------------------------------------------

$Domains = Read-Host "Please enter the Domain Names (comma-separated)"
if ([string]::IsNullOrWhiteSpace($Domains)) {
    Write-Warning "No target domains provided. Exiting."
    exit
}

$DomainArray = $Domains -split ',' | ForEach-Object { $_.Trim() }
$results = @()

foreach ($Domain in $DomainArray) {
    Write-Host "Querying DNS records for: $Domain" -ForegroundColor Cyan
    
    # Capture standard nslookup array output, silencing errors
    $nslookupResult = nslookup $Domain 2>$null
    
    # Pause execution sequentially to respect network query limits if applicable
    Start-Sleep -Seconds $DelaySeconds

    # Regex string extraction to capture details safely out of the command pipeline
    $ipAddress = $nslookupResult | Select-String -Pattern 'Address:\s*(.+)' | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
    $server    = $nslookupResult | Select-String -Pattern 'Server:\s*(.+)'  | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
    $resolved  = $nslookupResult | Select-String -Pattern 'Name:\s*(.+)'    | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }

    # Fallback checking to prevent blank field rows inside final tables
    $finalName      = if ($resolved) { $resolved } else { "Not Found" }
    $finalAddresses = if ($ipAddress) { $ipAddress -join ', ' } else { "Not Found" }
    $finalServer    = if ($server) { $server -join ', ' } else { "Unknown" }

    $results += [PSCustomObject]@{
        "Domain"        = $Domain
        "DNSServer"     = $finalServer
        "ResolvedName"  = $finalName
        "IPAddresses"   = $finalAddresses
    }
}

# Export the results collection directly to the dynamic path configuration
$results | Export-Csv -Path $OutputCSVPath -NoTypeInformation
Write-Host "`nProcess complete. Team results exported to: $OutputCSVPath" -ForegroundColor Green
