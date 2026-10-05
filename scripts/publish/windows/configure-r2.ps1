param(
    [string] $GitHubRepo = "dvorovrus/Generals-Mac-iOS-iPad",
    [string] $AwsProfile = "generals-r2"
)

$ErrorActionPreference = "Stop"

function ConvertFrom-Secure([Security.SecureString] $Secure) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Ensure-AwsCli {
    $aws = Get-Command aws -ErrorAction SilentlyContinue
    if ($aws) { return $aws.Source }

    Write-Host "AWS CLI not found. Installing awscli for current user..." -ForegroundColor Cyan
    & py -m pip install --user --disable-pip-version-check awscli 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Failed to install awscli." }

    $scriptsDir = (& py -c "import sysconfig; print(sysconfig.get_path('scripts', scheme='nt_user'))").Trim()
    $candidate = @(
        (Join-Path $scriptsDir "aws.cmd"),
        (Join-Path $scriptsDir "aws.exe"),
        (Join-Path $scriptsDir "aws")
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $candidate) { throw "AWS CLI launcher was not found after installation in: $scriptsDir" }

    if (($env:Path -split ';') -notcontains $scriptsDir) {
        $env:Path = "$scriptsDir;$env:Path"
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (($userPath -split ';') -notcontains $scriptsDir) {
            [Environment]::SetEnvironmentVariable("Path", "$scriptsDir;$userPath", "User")
        }
    }
    return [string]$candidate
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) is required."
}

Write-Host ""
Write-Host "Generals Hub - Cloudflare R2 setup" -ForegroundColor Cyan
Write-Host "Credentials are entered locally and are not printed." -ForegroundColor DarkGray
Write-Host ""

$AccountId = (Read-Host "Cloudflare Account ID").Trim()
$AccessKeyId = (Read-Host "R2 Access Key ID").Trim()
$SecretSecure = Read-Host "R2 Secret Access Key" -AsSecureString
$SecretAccessKey = ConvertFrom-Secure $SecretSecure
$Bucket = (Read-Host "R2 bucket name (example: generals-hub)").Trim()
$PublicBaseUrl = (Read-Host "Public base URL (r2.dev or custom domain, without trailing slash)").Trim().TrimEnd('/')

if (-not $AccountId -or -not $AccessKeyId -or -not $SecretAccessKey -or -not $Bucket -or -not $PublicBaseUrl) {
    throw "All values are required."
}
if (-not $PublicBaseUrl.StartsWith("https://")) {
    throw "Public base URL must start with https://"
}

$Aws = Ensure-AwsCli
$Endpoint = "https://$AccountId.r2.cloudflarestorage.com"

Write-Host "Configuring local AWS profile '$AwsProfile'..." -ForegroundColor Cyan
& $Aws configure set aws_access_key_id $AccessKeyId --profile $AwsProfile
& $Aws configure set aws_secret_access_key $SecretAccessKey --profile $AwsProfile
& $Aws configure set region auto --profile $AwsProfile

# Non-secret local settings can safely persist as user environment variables.
[Environment]::SetEnvironmentVariable("CLOUDFLARE_ACCOUNT_ID", $AccountId, "User")
[Environment]::SetEnvironmentVariable("R2_BUCKET", $Bucket, "User")
[Environment]::SetEnvironmentVariable("R2_PUBLIC_BASE_URL", $PublicBaseUrl, "User")
$env:CLOUDFLARE_ACCOUNT_ID = $AccountId
$env:R2_BUCKET = $Bucket
$env:R2_PUBLIC_BASE_URL = $PublicBaseUrl
$env:AWS_PROFILE = $AwsProfile

Write-Host "Checking R2 bucket access..." -ForegroundColor Cyan
& $Aws s3 ls "s3://$Bucket" --endpoint-url $Endpoint --region auto --profile $AwsProfile | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Cannot access R2 bucket. Check Account ID, key permissions and bucket name." }

$probeName = "setup/probe-$([Guid]::NewGuid().ToString('N')).txt"
$probeFile = Join-Path $env:TEMP "generals-r2-probe.txt"
"Generals Hub R2 probe $(Get-Date -Format o)" | Set-Content -Path $probeFile -Encoding utf8NoBOM

Write-Host "Checking public download URL..." -ForegroundColor Cyan
& $Aws s3 cp $probeFile "s3://$Bucket/$probeName" --endpoint-url $Endpoint --region auto --profile $AwsProfile --content-type "text/plain" --no-progress
if ($LASTEXITCODE -ne 0) { throw "Probe upload failed." }
try {
    $probeUrl = "$PublicBaseUrl/$probeName"
    $response = Invoke-WebRequest -UseBasicParsing -Uri $probeUrl -TimeoutSec 30
    if ($response.StatusCode -ne 200) { throw "Public probe returned HTTP $($response.StatusCode)." }
    Write-Host "Public URL OK: $probeUrl" -ForegroundColor Green
}
finally {
    & $Aws s3 rm "s3://$Bucket/$probeName" --endpoint-url $Endpoint --region auto --profile $AwsProfile | Out-Null
    Remove-Item $probeFile -Force -ErrorAction SilentlyContinue
}

Write-Host "Saving GitHub Actions secrets..." -ForegroundColor Cyan
$AccountId | gh secret set CLOUDFLARE_ACCOUNT_ID --repo $GitHubRepo
$AccessKeyId | gh secret set R2_ACCESS_KEY_ID --repo $GitHubRepo
$SecretAccessKey | gh secret set R2_SECRET_ACCESS_KEY --repo $GitHubRepo
$Bucket | gh secret set R2_BUCKET --repo $GitHubRepo

# Do not keep the plaintext secret in process state longer than needed.
$SecretAccessKey = $null

Write-Host ""
Write-Host "R2 READY" -ForegroundColor Green
Write-Host "Bucket:     $Bucket"
Write-Host "Public URL: $PublicBaseUrl"
Write-Host "AWS profile: $AwsProfile"
Write-Host "GitHub repo: $GitHubRepo"
Write-Host ""
Write-Host "Next command:" -ForegroundColor Cyan
Write-Host ".\scripts\publish\windows\publish-stable-mods-r2.ps1"
