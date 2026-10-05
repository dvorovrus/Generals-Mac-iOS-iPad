param(
    [Parameter(Mandatory=$true)]
    [string] $IpaPath,
    [ValidateSet("stable", "beta")]
    [string] $Channel = "beta",
    [string] $Version = "0.1.0",
    [int] $Build = 1,
    [string] $ReleaseNotes = "",
    [string] $Bucket = $env:R2_BUCKET,
    [string] $AccountId = $env:CLOUDFLARE_ACCOUNT_ID,
    [string] $PublicBaseUrl = $env:R2_PUBLIC_BASE_URL,
    [switch] $CommitAndPush
)

$ErrorActionPreference = "Stop"
$SourceRepo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$Catalog = Join-Path $SourceRepo "ios\hub\HubCatalog.json"
$Updater = Join-Path $SourceRepo "scripts\publish\update-hub-catalog.py"
$Python = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { "python" }

$IpaPath = (Resolve-Path $IpaPath).Path
if (-not $Bucket -or -not $AccountId -or -not $PublicBaseUrl) {
    throw "Set R2_BUCKET, CLOUDFLARE_ACCOUNT_ID and R2_PUBLIC_BASE_URL."
}
if (-not $env:AWS_ACCESS_KEY_ID -or -not $env:AWS_SECRET_ACCESS_KEY) {
    throw "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY to an R2 API token pair."
}
$Aws = Get-Command aws -ErrorAction SilentlyContinue
if (-not $Aws) { throw "AWS CLI is required (aws command not found)." }

$SafeVersion = ($Version -replace '[^A-Za-z0-9._+-]', '-')
$FileName = Split-Path $IpaPath -Leaf
$Key = "hub/$Channel/$SafeVersion/$FileName"
$Endpoint = "https://$AccountId.r2.cloudflarestorage.com"
$PublicBaseUrl = $PublicBaseUrl.TrimEnd('/')
$PackageUrl = "$PublicBaseUrl/$Key"
$CatalogUrl = "$PublicBaseUrl/catalog.json"

Write-Host "Uploading Generals Hub $Version build $Build ($Channel)..." -ForegroundColor Cyan
& $Aws.Source s3 cp $IpaPath "s3://$Bucket/$Key" --endpoint-url $Endpoint --region auto --no-progress
if ($LASTEXITCODE -ne 0) { throw "R2 IPA upload failed." }

$Hash = (Get-FileHash $IpaPath -Algorithm SHA256).Hash.ToLowerInvariant()
$Bytes = (Get-Item $IpaPath).Length

& $Python $Updater --catalog $Catalog --remote-catalog-url $CatalogUrl hub `
    --channel $Channel --version $Version --build $Build `
    --url $PackageUrl --sha256 $Hash --bytes $Bytes --release-notes $ReleaseNotes
if ($LASTEXITCODE -ne 0) { throw "Catalog update failed." }

& $Aws.Source s3 cp $Catalog "s3://$Bucket/catalog.json" --endpoint-url $Endpoint --region auto `
    --content-type "application/json; charset=utf-8" --cache-control "no-cache, max-age=60" --no-progress
if ($LASTEXITCODE -ne 0) { throw "R2 catalog upload failed." }

if ($CommitAndPush) {
    git -C $SourceRepo add -- ios/hub/HubCatalog.json
    git -C $SourceRepo commit -m "release(hub): publish $Version build $Build to $Channel [skip ci]"
    if ($LASTEXITCODE -ne 0) { throw "Catalog git commit failed." }
    git -C $SourceRepo push
    if ($LASTEXITCODE -ne 0) { throw "Catalog git push failed." }
}

Write-Host ""
Write-Host "PUBLISHED" -ForegroundColor Green
Write-Host "Hub:     $Version ($Build)"
Write-Host "Channel: $Channel"
Write-Host "URL:     $PackageUrl"
Write-Host "SHA256:  $Hash"
Write-Host "Catalog: $CatalogUrl"
