
$clients = @()
$payments = @()

$firstNames = @("Ali", "Ahmed", "Bilal", "Chaudhry", "David", "Ehtesham", "Fahad", "Hamza", "Imran", "Junaid", "Kamran", "Liaqat", "Moharyar", "Noman", "Osama", "Pervez", "Qasim", "Rizwan", "Saad", "Tariq", "Usman", "Vicky", "Waseem", "Xavier", "Yasir", "Zain")
$lastNames = @("Khan", "Smith", "Butt", "Sheikh", "Jutt", "Gupta", "Doe", "Malik", "Raja", "Shah", "Ansari", "Qureshi", "Akram", "Afzal", "Baig", "Bhatti")
$membershipTypes = @("Cardio", "NonCardio", "CardioPlusNonCardio")
$statuses = @("Active", "Inactive")
$regFeeStatuses = @("Paid", "PartiallyPaid", "Pending")

$fees = @{
    "Cardio" = 1500
    "NonCardio" = 800
    "CardioPlusNonCardio" = 2300
    "Registration" = 400
}

$startClientId = 1
$startRegNo = 1
$paymentCounter = 1
$currentYear = 2026
$dataDirectory = "Data"

if (-not (Test-Path $dataDirectory)) {
    New-Item -ItemType Directory -Path $dataDirectory | Out-Null
}

for ($i = 0; $i -lt 50; $i++) {
    $clientIdNum = $startClientId + $i
    $regNoNum = $startRegNo + $i
    
    $clientId = "GYM-{0:D5}" -f $clientIdNum
    $regNo = "FA-{0:D6}" -f $regNoNum
    
    $fn = $firstNames | Get-Random
    $ln = $lastNames | Get-Random
    $fullName = "$fn $ln"
    $phone = "03{0}-{1}" -f (Get-Random -Minimum 10 -Maximum 49), (Get-Random -Minimum 1000000 -Maximum 9999999)
    
    $joinYear = (Get-Random -InputObject @(2025, 2026))
    $joinMonth = if ($joinYear -eq 2026) { Get-Random -Minimum 1 -Maximum 3 } else { Get-Random -Minimum 1 -Maximum 13 }
    $joinDay = Get-Random -Minimum 1 -Maximum 29
    $joinDate = Get-Date -Year $joinYear -Month $joinMonth -Day $joinDay -Hour 0 -Minute 0 -Second 0
    
    $status = $statuses | Get-Random
    $lastAttendance = $null
    
    if ($status -eq "Active") {
        $days = Get-Random -Minimum 0 -Maximum 30
        $lastAttendance = $joinDate.AddDays($days)
        if ($lastAttendance -gt (Get-Date)) { $lastAttendance = Get-Date }
    } else {
        $daysAgo = Get-Random -Minimum 30 -Maximum 120
        $lastAttendance = (Get-Date).AddDays(-$daysAgo)
    }
    
    $membership = $membershipTypes | Get-Random
    $regFeeStatus = $regFeeStatuses | Get-Random
    
    $regFeeDue = $fees["Registration"]
    $regFeePaid = 0
    
    if ($regFeeStatus -eq "Paid") { $regFeePaid = $regFeeDue }
    elseif ($regFeeStatus -eq "PartiallyPaid") { $regFeePaid = Get-Random -Minimum 100 -Maximum 300 }
    
    $regFeeBalance = $regFeeDue - $regFeePaid
    
    $client = [PSCustomObject]@{
        ClientId = $clientId
        RegistrationNumber = $regNo
        FullName = $fullName
        Phone = $phone
        JoinDate = $joinDate.ToString("yyyy-MM-ddTHH:mm:ss")
        Status = $status
        MembershipType = $membership
        RegistrationFeeStatus = $regFeeStatus
        RegistrationFeeDue = $regFeeDue
        RegistrationFeePaid = $regFeePaid
        RegistrationFeeBalance = $regFeeBalance
        LastAttendanceDate = if ($lastAttendance) { $lastAttendance.ToString("yyyy-MM-ddTHH:mm:ss") } else { $null }
        BillingStartDate = $joinDate.ToString("yyyy-MM-ddTHH:mm:ss")
        CreatedAt = $joinDate.ToString("yyyy-MM-ddTHH:mm:ss")
        ProfilePicturePath = $null
    }
    $clients += $client
    
    # Registration Payment
    if ($regFeePaid -gt 0) {
        $payId = "PAY-$joinYear-{0:D5}" -f $paymentCounter
        $paymentCounter++
        
        $payment = [PSCustomObject]@{
            PaymentId = $payId
            ClientId = $clientId
            Type = "Registration"
            Month = 0
            Year = $joinYear
            AmountDue = $regFeeDue
            AmountPaid = $regFeePaid
            TotalPaid = $regFeePaid
            RemainingBalance = $regFeeBalance
            PaymentStatus = $regFeeStatus
            PaymentDate = $joinDate.ToString("yyyy-MM-ddTHH:mm:ss")
        }
        $payments += $payment
    }
    
    # Monthly Payments
    if ($joinYear -eq 2026) { $startM = $joinMonth } else { $startM = 1 }
    
    for ($m = $startM; $m -le 2; $m++) {
        # Random skip if inactive
        if ($status -eq "Inactive" -and (Get-Random -Minimum 0 -Maximum 10) -gt 7) { continue }
        
        $monthlyStatus = ("Paid", "Pending", "PartiallyPaid") | Get-Random
        $amountDue = $fees[$membership]
        $amountPaid = 0
        
        if ($monthlyStatus -eq "Paid") { $amountPaid = $amountDue }
        elseif ($monthlyStatus -eq "PartiallyPaid") { $amountPaid = Get-Random -Minimum 500 -Maximum ($amountDue - 100) }
        
        $bal = $amountDue - $amountPaid
        
        $payId = "PAY-$currentYear-{0:D5}" -f $paymentCounter
        $paymentCounter++
        
        $payDate = (Get-Date -Year $currentYear -Month $m -Day (Get-Random -Minimum 1 -Maximum 28))
        
        $payment = [PSCustomObject]@{
            PaymentId = $payId
            ClientId = $clientId
            Type = "Monthly"
            Month = $m
            Year = $currentYear
            AmountDue = $amountDue
            AmountPaid = $amountPaid
            TotalPaid = $amountPaid
            RemainingBalance = $bal
            PaymentStatus = $monthlyStatus
            PaymentDate = $payDate.ToString("yyyy-MM-ddTHH:mm:ss")
        }
        $payments += $payment
    }
}

$clients | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $dataDirectory "clients.json")

$paymentsByYear = $payments | Group-Object Year
foreach ($yearGroup in $paymentsByYear) {
    $paymentsPath = Join-Path $dataDirectory ("payments_{0}.json" -f $yearGroup.Name)
    $yearGroup.Group | ConvertTo-Json -Depth 5 | Set-Content $paymentsPath
}

Write-Host "LastClientNumber: $($startClientId + 49)"
Write-Host "LastRegistrationNumber: $($startRegNo + 49)"
Write-Host "LastPaymentNumber: $($paymentCounter - 1)"
