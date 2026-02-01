#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ----------------------------
# Config
# ----------------------------
$ScriptName = "windows_baseline"
$HostName   = $env:COMPUTERNAME
$OS         = "windows"
$Timestamp  = (Get-Date).ToString("o")  # ISO 8601
$RunId      = (Get-Date).ToString("yyyyMMdd_HHmmss")

$LogDir  = ".\logs"
$LogFile = Join-Path $LogDir ("win11_baseline_{0}.jsonl" -f $RunId)

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

# ----------------------------
# Helpers
# ----------------------------
function Write-JsonlLog {
    param(
        [Parameter(Mandatory=$true)][string]$Check,
        [Parameter(Mandatory=$true)][ValidateSet("OK","WARN","FAIL")][string]$Status,
        [Parameter(Mandatory=$true)][string]$Details
    )

    $entry = [ordered]@{
        timestamp = $Timestamp
        host      = $HostName
        os        = $OS
        script    = $ScriptName
        check     = $Check
        status    = $Status
        details   = $Details
    }

    ($entry | ConvertTo-Json -Compress) | Add-Content -Path $LogFile -Encoding UTF8
}

function Write-RunSummaryAndExit {
    param([int]$ExitCode)

    switch ($ExitCode) {
        0 { Write-JsonlLog -Check "run_summary" -Status "OK"   -Details "Alla kontroller OK." }
        1 { Write-JsonlLog -Check "run_summary" -Status "WARN" -Details "Minst en kontroll gav WARN." }
        default { Write-JsonlLog -Check "run_summary" -Status "FAIL" -Details "Minst en kontroll gav FAIL eller tekniskt fel." }
    }

    Write-Host "Klart. Logg: $LogFile"
    exit $ExitCode
}

# ----------------------------
# Check 1: Windows Defender Firewall enabled?
# ----------------------------
function Check-FirewallEnabled {
    try {
        $profiles = Get-NetFirewallProfile | Select-Object Name, Enabled
        $disabled = $profiles | Where-Object { $_.Enabled -eq $false }

        if ($null -ne $disabled -and $disabled.Count -gt 0) {
            $names = ($disabled | ForEach-Object { $_.Name }) -join ", "
            Write-JsonlLog -Check "firewall_enabled" -Status "FAIL" -Details "Brandväggen är AV för profiler: $names."
            return 2
        }

        $enabledNames = ($profiles | Where-Object { $_.Enabled -eq $true } | ForEach-Object { $_.Name }) -join ", "
        Write-JsonlLog -Check "firewall_enabled" -Status "OK" -Details "Brandväggen är PÅ för profiler: $enabledNames."
        return 0
    }
    catch {
        Write-JsonlLog -Check "firewall_enabled" -Status "FAIL" -Details ("Tekniskt fel vid kontroll av brandvägg: " + $_.Exception.Message)
        return 2
    }
}

# ----------------------------
# Check 2: Local Administrators group members
# ----------------------------
function Check-LocalAdministrators {
    try {
        # "Administrators" är gruppens tekniska namn i Windows, oavsett språkvisning.
        $members = Get-LocalGroupMember -Group "Administrators" | Select-Object Name, ObjectClass

        if ($null -eq $members -or $members.Count -eq 0) {
            Write-JsonlLog -Check "local_admins" -Status "WARN" -Details "Kunde inte hitta några medlemmar i Administrators-gruppen (oväntat)."
            return 1
        }

        # Vi gör det enkelt: rapportera count + lista (max 10 för läsbarhet).
        $count = $members.Count
        $top   = ($members | Select-Object -First 10 | ForEach-Object { "$($_.Name) [$($_.ObjectClass)]" }) -join "; "

        $details = "Antal medlemmar i Administrators: $count. Exempel (max 10): $top"
        Write-JsonlLog -Check "local_admins" -Status "OK" -Details $details
        return 0
    }
    catch {
        Write-JsonlLog -Check "local_admins" -Status "FAIL" -Details ("Tekniskt fel vid kontroll av lokala administratörer: " + $_.Exception.Message)
        return 2
    }
}

# ----------------------------
# Main
# ----------------------------
Write-JsonlLog -Check "run_start" -Status "OK" -Details ("Startar kontroller. Loggfil: " + $LogFile)

$exitCode = 0

$rc1 = Check-FirewallEnabled
if ($rc1 -gt $exitCode) { $exitCode = $rc1 }

$rc2 = Check-LocalAdministrators
if ($rc2 -gt $exitCode) { $exitCode = $rc2 }

Write-RunSummaryAndExit -ExitCode $exitCode
