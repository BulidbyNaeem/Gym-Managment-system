[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

function ConvertTo-DateTimeOrMin {
    param([object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return [DateTime]::MinValue
    }

    return [DateTime]::Parse([string]$Value)
}

function Read-JsonArray {
    param([string]$Path)

    $data = Get-Content $Path -Raw | ConvertFrom-Json

    if ($null -eq $data) {
        return @()
    }

    if ($data -is [System.Array]) {
        return $data
    }

    return @($data)
}

function Get-NextClientId {
    param(
        [ref]$SystemConfig,
        [System.Collections.Generic.HashSet[string]]$UsedIds
    )

    do {
        $SystemConfig.Value.LastClientNumber++
        $candidate = "GYM-{0:D5}" -f $SystemConfig.Value.LastClientNumber
    } while ($UsedIds.Contains($candidate))

    $UsedIds.Add($candidate) | Out-Null
    return $candidate
}

function Get-NextRegistrationNumber {
    param(
        [ref]$SystemConfig,
        [System.Collections.Generic.HashSet[string]]$UsedRegistrationNumbers
    )

    do {
        $SystemConfig.Value.LastRegistrationNumber++
        $candidate = "FA-{0:D6}" -f $SystemConfig.Value.LastRegistrationNumber
    } while ($UsedRegistrationNumbers.Contains($candidate))

    $UsedRegistrationNumbers.Add($candidate) | Out-Null
    return $candidate
}

function Get-MatchingPayments {
    param(
        [object[]]$Payments,
        [string]$OriginalClientId,
        [DateTime]$CreatedAt
    )

    $windowStart = $CreatedAt.AddMinutes(-10)
    $windowEnd = $CreatedAt.AddHours(36)

    return @(
        $Payments | Where-Object {
            $_.ClientId -eq $OriginalClientId -and
            (ConvertTo-DateTimeOrMin $_.PaymentDate) -ge $windowStart -and
            (ConvertTo-DateTimeOrMin $_.PaymentDate) -le $windowEnd
        }
    )
}

function Get-MatchingAttendance {
    param(
        [object[]]$AttendanceRecords,
        [string]$OriginalClientId,
        [DateTime]$CreatedAt,
        [string]$ClientName
    )

    $windowStart = $CreatedAt.AddMinutes(-10)
    $windowEnd = $CreatedAt.AddHours(36)

    return @(
        $AttendanceRecords | Where-Object {
            $_.ClientId -eq $OriginalClientId -and
            $_.ClientName -eq $ClientName -and
            (ConvertTo-DateTimeOrMin $_.AttendanceDate) -ge $windowStart -and
            (ConvertTo-DateTimeOrMin $_.AttendanceDate) -le $windowEnd
        }
    )
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataDir = Join-Path $root "Data"
$clientsPath = Join-Path $dataDir "clients.json"
$systemPath = Join-Path $dataDir "system.json"
$backupDir = Join-Path $root ".codexobj\duplicate-client-repair-backups"

$clients = Read-JsonArray -Path $clientsPath
$systemConfig = Get-Content $systemPath -Raw | ConvertFrom-Json

$paymentFiles = @(Get-ChildItem $dataDir -Filter "payments_*.json" | Sort-Object Name)
$paymentBuckets = @{}
$allPayments = @()
foreach ($file in $paymentFiles) {
    $items = Read-JsonArray -Path $file.FullName
    $paymentBuckets[$file.FullName] = $items
    $allPayments += $items
}

$attendanceFiles = @(Get-ChildItem $dataDir -Filter "attendance_*.json" | Sort-Object Name)
$attendanceBuckets = @{}
$allAttendance = @()
foreach ($file in $attendanceFiles) {
    $items = Read-JsonArray -Path $file.FullName
    $attendanceBuckets[$file.FullName] = $items
    $allAttendance += $items
}

$usedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$usedRegistrationNumbers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($client in $clients) {
    if (-not [string]::IsNullOrWhiteSpace($client.ClientId)) {
        $usedIds.Add([string]$client.ClientId) | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($client.RegistrationNumber)) {
        $usedRegistrationNumbers.Add([string]$client.RegistrationNumber) | Out-Null
    }
}

$duplicateGroups = @(
    $clients |
        Group-Object ClientId |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) -and $_.Count -gt 1 }
)

if ($duplicateGroups.Count -eq 0) {
    Write-Host "No duplicate ClientId values found."
    exit 0
}

$report = New-Object System.Collections.Generic.List[object]

foreach ($group in $duplicateGroups) {
    $orderedClients = @(
        $group.Group |
            Sort-Object @{ Expression = { ConvertTo-DateTimeOrMin $_.CreatedAt } }, @{ Expression = { ConvertTo-DateTimeOrMin $_.JoinDate } }
    )

    $primary = $orderedClients[0]

    foreach ($duplicate in $orderedClients | Select-Object -Skip 1) {
        $oldClientId = [string]$duplicate.ClientId
        $oldRegistrationNumber = [string]$duplicate.RegistrationNumber
        $createdAt = ConvertTo-DateTimeOrMin $duplicate.CreatedAt

        $usedIds.Remove($oldClientId) | Out-Null
        $usedRegistrationNumbers.Remove($oldRegistrationNumber) | Out-Null

        $newClientId = Get-NextClientId -SystemConfig ([ref]$systemConfig) -UsedIds $usedIds
        $newRegistrationNumber = Get-NextRegistrationNumber -SystemConfig ([ref]$systemConfig) -UsedRegistrationNumbers $usedRegistrationNumbers

        $matchingPayments = Get-MatchingPayments -Payments $allPayments -OriginalClientId $oldClientId -CreatedAt $createdAt
        $matchingAttendance = Get-MatchingAttendance -AttendanceRecords $allAttendance -OriginalClientId $oldClientId -CreatedAt $createdAt -ClientName ([string]$duplicate.FullName)

        $duplicate.ClientId = $newClientId
        $duplicate.RegistrationNumber = $newRegistrationNumber

        foreach ($payment in $matchingPayments) {
            $payment.ClientId = $newClientId
        }

        foreach ($attendanceRecord in $matchingAttendance) {
            $attendanceRecord.ClientId = $newClientId
            $attendanceRecord.RegistrationNumber = $newRegistrationNumber
        }

        $report.Add([pscustomobject]@{
                OriginalClientId = $oldClientId
                OriginalRegistrationNumber = $oldRegistrationNumber
                PrimaryClient = [string]$primary.FullName
                ReassignedClient = [string]$duplicate.FullName
                NewClientId = $newClientId
                NewRegistrationNumber = $newRegistrationNumber
                PaymentsMoved = @($matchingPayments | ForEach-Object { $_.PaymentId }) -join ", "
                AttendanceMoved = @($matchingAttendance | ForEach-Object { $_.AttendanceId }) -join ", "
            }) | Out-Null
    }
}

$report | Format-Table -AutoSize | Out-String | Write-Host

if (-not $Apply) {
    Write-Host "Preview only. Re-run with -Apply to write changes."
    exit 0
}

if ($PSCmdlet.ShouldProcess($dataDir, "Repair duplicate clients and rewrite JSON data")) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    Copy-Item $clientsPath (Join-Path $backupDir "clients_$timestamp.json") -Force
    Copy-Item $systemPath (Join-Path $backupDir "system_$timestamp.json") -Force

    foreach ($file in $paymentFiles) {
        Copy-Item $file.FullName (Join-Path $backupDir ("{0}_{1}" -f $timestamp, $file.Name)) -Force
    }

    foreach ($file in $attendanceFiles) {
        Copy-Item $file.FullName (Join-Path $backupDir ("{0}_{1}" -f $timestamp, $file.Name)) -Force
    }

    $clients | ConvertTo-Json -Depth 10 | Set-Content $clientsPath -Encoding UTF8
    $systemConfig | ConvertTo-Json -Depth 10 | Set-Content $systemPath -Encoding UTF8

    foreach ($entry in $paymentBuckets.GetEnumerator()) {
        $entry.Value | ConvertTo-Json -Depth 10 | Set-Content $entry.Key -Encoding UTF8
    }

    foreach ($entry in $attendanceBuckets.GetEnumerator()) {
        $entry.Value | ConvertTo-Json -Depth 10 | Set-Content $entry.Key -Encoding UTF8
    }

    Write-Host "Duplicate client repair applied successfully."
    Write-Host "Backups saved in: $backupDir"
}
