<#
.SYNOPSIS
    Provisions Microsoft 365 user accounts for Cloud Nine Wellness staff.

.DESCRIPTION
    Creates user accounts for all three studio locations (King West, Yorkville, Liberty Village).
    Assigns Microsoft 365 Business Standard licenses, sets usage location to Canada,
    and organizes accounts by role (Instructor, Front Desk, Studio Manager).
    All accounts follow the UPN format: firstname.lastname@cloudninewellness.onmicrosoft.com

.AUTHOR
    Md Rahat Islam Anik

.PREREQUISITES
    Run 01-Connect-M365Tenant.ps1 first to establish authenticated sessions.

.USAGE
    .-Provision-StaffAccounts.ps1
#>

#region --- Configuration ---
$TenantDomain   = "cloudninewellness.onmicrosoft.com"
$UsageLocation  = "CA"   # Canada
$LicenseSKU     = "cloudninewellness:O365_BUSINESS_PREMIUM"  # M365 Business Standard
#endregion

#region --- Helper: Random Temp Password ---
# Generates a unique 14-character temp password per user instead of a single shared
# static value. Sharing one temp password across an entire batch of new accounts is
# a real credential-stuffing/brute-force risk during the window before first sign-in.
function New-RandomTempPassword {
    param([int]$Length = 14)
    $upper   = 65..90 | ForEach-Object { [char]$_ }
    $lower   = 97..122 | ForEach-Object { [char]$_ }
    $digits  = 48..57 | ForEach-Object { [char]$_ }
    $special = @('!','@','#','$','%','&','*')

    # Guarantee at least one of each character class, then fill the rest randomly
    $passwordChars = @(
        ($upper   | Get-Random)
        ($lower   | Get-Random)
        ($digits  | Get-Random)
        ($special | Get-Random)
    )
    $allChars = $upper + $lower + $digits + $special
    $passwordChars += 1..($Length - $passwordChars.Count) | ForEach-Object { $allChars | Get-Random }

    # Shuffle so the guaranteed characters aren't always in the same positions
    return -join ($passwordChars | Sort-Object { Get-Random })
}
#endregion

#region --- Staff Account Definitions ---
# Organized by studio location and role
$StaffAccounts = @(
    # King West Studio
    @{ FirstName="Sarah";   LastName="Mitchell";   Role="Studio Manager"; Location="King West";     Dept="Management" },
    @{ FirstName="James";   LastName="Okafor";     Role="Instructor";     Location="King West";     Dept="Fitness" },
    @{ FirstName="Priya";   LastName="Sharma";     Role="Instructor";     Location="King West";     Dept="Fitness" },
    @{ FirstName="Lucas";   LastName="Ferreira";   Role="Front Desk";     Location="King West";     Dept="Operations" },
    @{ FirstName="Emma";    LastName="Thornton";   Role="Front Desk";     Location="King West";     Dept="Operations" },

    # Yorkville Studio
    @{ FirstName="Daniel";  LastName="Park";       Role="Studio Manager"; Location="Yorkville";     Dept="Management" },
    @{ FirstName="Aisha";   LastName="Nwosu";      Role="Instructor";     Location="Yorkville";     Dept="Fitness" },
    @{ FirstName="Marco";   LastName="Deluca";     Role="Instructor";     Location="Yorkville";     Dept="Fitness" },
    @{ FirstName="Fatima";  LastName="Al-Hassan";  Role="Front Desk";     Location="Yorkville";     Dept="Operations" },
    @{ FirstName="Tyler";   LastName="Brooks";     Role="Front Desk";     Location="Yorkville";     Dept="Operations" },

    # Liberty Village Studio
    @{ FirstName="Natasha"; LastName="Kowalski";   Role="Studio Manager"; Location="Liberty Village"; Dept="Management" },
    @{ FirstName="Omar";    LastName="Diallo";     Role="Instructor";     Location="Liberty Village"; Dept="Fitness" },
    @{ FirstName="Chloe";   LastName="Nguyen";     Role="Instructor";     Location="Liberty Village"; Dept="Fitness" },
    @{ FirstName="Ravi";    LastName="Patel";      Role="Front Desk";     Location="Liberty Village"; Dept="Operations" },
    @{ FirstName="Sofia";   LastName="Mendez";     Role="Front Desk";     Location="Liberty Village"; Dept="Operations" },

    # Corporate/Operations
    @{ FirstName="Marcus";  LastName="Reid";       Role="Operations Director"; Location="Corporate"; Dept="Management" },
    @{ FirstName="Jennifer";LastName="Wu";         Role="HR Coordinator"; Location="Corporate";     Dept="HR" }
)
#endregion

#region --- Create User Accounts ---
Write-Host "`n[INFO] Provisioning $($StaffAccounts.Count) staff accounts..." -ForegroundColor Cyan

$SuccessCount = 0
$FailCount    = 0
$CredentialHandoff = @()   # unique temp password per user, for secure 1:1 handoff — never logged/emailed as a batch

foreach ($Staff in $StaffAccounts) {
    $UPN         = "$($Staff.FirstName.ToLower()).$($Staff.LastName.ToLower().Replace('-',''))@$TenantDomain"
    $DisplayName = "$($Staff.FirstName) $($Staff.LastName)"
    $MailNick    = "$($Staff.FirstName.ToLower())$($Staff.LastName.ToLower().Replace('-','').Replace(' ',''))"
    $TempPassword = New-RandomTempPassword

    $PasswordProfile = @{
        Password                      = $TempPassword
        ForceChangePasswordNextSignIn = $true
    }

    try {
        $NewUser = New-MgUser `
            -DisplayName      $DisplayName `
            -UserPrincipalName $UPN `
            -MailNickname     $MailNick `
            -GivenName        $Staff.FirstName `
            -Surname          $Staff.LastName `
            -JobTitle         $Staff.Role `
            -Department       $Staff.Dept `
            -UsageLocation    $UsageLocation `
            -PasswordProfile  $PasswordProfile `
            -AccountEnabled   $true `
            -ErrorAction Stop

        # Assign M365 Business Standard license
        $LicenseObj = @{
            AddLicenses    = @(@{ SkuId = (Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq "O365_BUSINESS_PREMIUM" }).SkuId })
            RemoveLicenses = @()
        }
        Set-MgUserLicense -UserId $NewUser.Id -AddLicenses $LicenseObj.AddLicenses -RemoveLicenses $LicenseObj.RemoveLicenses | Out-Null

        Write-Host "  [OK] Created: $DisplayName ($UPN) — $($Staff.Role) @ $($Staff.Location)" -ForegroundColor Green
        $CredentialHandoff += [PSCustomObject]@{
            DisplayName  = $DisplayName
            UPN          = $UPN
            TempPassword = $TempPassword
        }
        $SuccessCount++
    } catch {
        Write-Host "  [FAIL] $DisplayName ($UPN): $_" -ForegroundColor Red
        $FailCount++
    }
}
#endregion

#region --- Summary ---
Write-Host "`n[SUMMARY] Provisioning complete." -ForegroundColor Cyan
Write-Host "  Accounts created : $SuccessCount"
Write-Host "  Failures         : $FailCount"

# Export unique temp passwords to a local file for secure 1:1 handoff to each new hire.
# This file contains plaintext credentials — treat it as sensitive: hand off individually,
# then delete it. Do not email it as a batch or leave it in a shared location.
$HandoffPath = Join-Path $PSScriptRoot "staff-temp-credentials-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$CredentialHandoff | Export-Csv -Path $HandoffPath -NoTypeInformation
Write-Host "  Temp credentials exported to: $HandoffPath (sensitive — handle per handoff policy, then delete)" -ForegroundColor Yellow

Write-Host "[NEXT] Run 03-Configure-Groups.ps1 to create and populate security groups.`n" -ForegroundColor Cyan
#endregion
