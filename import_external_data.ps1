param(
    [string]$SourceDataPath = (Join-Path $PSScriptRoot "ImportData"),
    [string]$TargetDataPath = (Join-Path $PSScriptRoot "Data")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw

    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "File is empty: $Path"
    }

    return $raw | ConvertFrom-Json
}

function Get-MaxTrailingNumber {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    $max = 0

    foreach ($item in $Items) {
        $value = $item.$PropertyName
        if ($null -eq $value) {
            continue
        }

        $text = [string]$value
        if ($text -match '(\d+)$') {
            $number = [int]$matches[1]
            if ($number -gt $max) {
                $max = $number
            }
        }
    }

    return $max
}

$resolvedSourcePath = $SourceDataPath

if (-not [System.IO.Path]::IsPathRooted($resolvedSourcePath)) {
    $resolvedSourcePath = Join-Path $PSScriptRoot $resolvedSourcePath
}

if (-not (Test-Path -LiteralPath $resolvedSourcePath)) {
    throw "Source data folder not found: $resolvedSourcePath. Copy the export files into this folder or pass -SourceDataPath explicitly."
}

New-Item -ItemType Directory -Path $TargetDataPath -Force | Out-Null

$clientsSource = Join-Path $resolvedSourcePath "clients.json"
$sourceClients = @(Read-JsonFile -Path $clientsSource | ForEach-Object { $_ })

$paymentFiles = @(Get-ChildItem -LiteralPath $resolvedSourcePath -Filter "payments_*.json" -File |
    Where-Object { $_.Length -gt 2 } |
    Sort-Object Name)

$allPayments = @()

foreach ($file in $paymentFiles) {
    $payments = @(Read-JsonFile -Path $file.FullName | ForEach-Object { $_ })
    $allPayments += $payments
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $TargetDataPath $file.Name) -Force
}

Copy-Item -LiteralPath $clientsSource -Destination (Join-Path $TargetDataPath "clients.json") -Force

$targetSystemPath = Join-Path $TargetDataPath "system.json"
$systemConfig = $null

if (Test-Path -LiteralPath $targetSystemPath) {
    try {
        $systemConfig = Read-JsonFile -Path $targetSystemPath
    }
    catch {
        $systemConfig = $null
    }
}

if ($null -eq $systemConfig) {
    $systemConfig = [pscustomobject]@{
        CurrentYear = 0
        RegistrationFee = 400
        CardioMonthlyFee = 2000
        NonCardioMonthlyFee = 1000
        CardioPlusNonCardioMonthlyFee = 3000
        AutoDeactivateDays = 60
        LastClientNumber = 0
        LastPaymentNumber = 0
        LastRegistrationNumber = 0
        WhatsAppTemplate = "Asalam-o-alikom {Name}, apka gym balance PKR {Amount} pending hai. Shukriya!"
    }
}

$paymentYears = @($allPayments | ForEach-Object { $_.Year } | Where-Object { $_ -is [int] })
$latestPaymentYear = if ($paymentYears.Count -gt 0) { ($paymentYears | Measure-Object -Maximum).Maximum } else { [DateTime]::Now.Year }

$systemConfig.CurrentYear = [int]$latestPaymentYear
$systemConfig.LastClientNumber = Get-MaxTrailingNumber -Items $sourceClients -PropertyName "ClientId"
$systemConfig.LastRegistrationNumber = Get-MaxTrailingNumber -Items $sourceClients -PropertyName "RegistrationNumber"
$systemConfig.LastPaymentNumber = Get-MaxTrailingNumber -Items $allPayments -PropertyName "PaymentId"

$systemConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $targetSystemPath -Encoding UTF8

Write-Host "Imported clients: $($sourceClients.Count)"
Write-Host "Imported payment files: $($paymentFiles.Count)"
Write-Host "Imported payments: $($allPayments.Count)"
Write-Host "Source path used: $resolvedSourcePath"
Write-Host "CurrentYear set to: $($systemConfig.CurrentYear)"
Write-Host "LastClientNumber set to: $($systemConfig.LastClientNumber)"
Write-Host "LastRegistrationNumber set to: $($systemConfig.LastRegistrationNumber)"
Write-Host "LastPaymentNumber set to: $($systemConfig.LastPaymentNumber)"
