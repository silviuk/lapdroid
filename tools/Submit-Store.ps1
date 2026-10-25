param([Parameter(Mandatory)][string]$CandidateDirectory, [string]$ResumeSubmissionId = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/StorePublishing.ps1"
$candidate = Assert-LapdroidCandidate -Directory $CandidateDirectory
$version = $candidate.version
$shots = @(Get-LapdroidStoreScreenshots -Directory $CandidateDirectory -Version $version)
$packageName = "Lapdroid-$version.0-x64.msix"
$notes = (Get-Content -LiteralPath (Join-Path $CandidateDirectory 'release-notes.txt') -Raw).Trim()
$listing = Get-Content -LiteralPath (Join-Path $CandidateDirectory 'listing-en-US.json') -Raw | ConvertFrom-Json
foreach ($name in @('MS_STORE_TENANT_ID','MS_STORE_CLIENT_ID','MS_STORE_CLIENT_SECRET')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) { throw "Missing Actions secret: $name" }
}
if ($env:MS_STORE_TENANT_ID -notmatch '^[0-9a-fA-F-]{36}$' -or $env:MS_STORE_CLIENT_ID -notmatch '^[0-9a-fA-F-]{36}$') { throw 'Tenant and client IDs must be GUIDs.' }
if ($ResumeSubmissionId -and $ResumeSubmissionId -notmatch '^[0-9]+$') { throw 'Resume ID must be a numeric API-created submission ID.' }
try {
    $token = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$env:MS_STORE_TENANT_ID/oauth2/v2.0/token" -ContentType 'application/x-www-form-urlencoded' -Body @{
        grant_type='client_credentials'; client_id=$env:MS_STORE_CLIENT_ID; client_secret=$env:MS_STORE_CLIENT_SECRET; scope='https://manage.devcenter.microsoft.com/.default'
    }
} catch { throw 'Partner Center authentication failed. Check the tenant, client, secret, and publisher association. Sensitive response details are omitted.' }
if (-not $token.access_token) { throw 'Authentication returned no access token.' }
Write-Output "::add-mask::$($token.access_token)"
$headers = @{Authorization="Bearer $($token.access_token)";Accept='application/json'}
function Request([string]$Method, [string]$Uri, $Body = $null) {
    try {
        $params = @{ Method=$Method; Uri=$Uri; Headers=$headers; ContentType='application/json'; ErrorAction='Stop' }
        if ($null -ne $Body) { $params.Body = $Body | ConvertTo-Json -Depth 50 -Compress }
        Invoke-RestMethod @params
    } catch { throw "Partner Center $Method failed. Review the submission in Partner Center; credentials and signed URLs are omitted from this error." }
}
$appUri = 'https://manage.devcenter.microsoft.com/v1.0/my/applications/9N1L1QZJNT6Z'
$app = Request GET $appUri
Assert-LapdroidApiBootstrap -Application $app
$subUri = $null
if ($app.pendingApplicationSubmission.id) {
    $id = [string]$app.pendingApplicationSubmission.id
    $subUri = "$appUri/submissions/$id"
    $status = Request GET "$subUri/status"
    $sub = Request GET $subUri
    $action = Get-LapdroidSubmissionAction -Status $status.status
    if ($action -eq 'Verify') {
        Assert-LapdroidSubmission -Submission $sub -Version $version -AllowPendingUpload:($status.status -eq 'CommitStarted')
        Assert-LapdroidListingScreenshots -Submission $sub -Screenshots $shots
        "Existing submission $id matches $version. Status: $($status.status). Only Published means live." | Tee-Object -Variable result
        if ($env:GITHUB_STEP_SUMMARY) { $result >> $env:GITHUB_STEP_SUMMARY }; return
    }
    if ($action -ne 'Edit' -or $ResumeSubmissionId -cne $id) {
        throw "Existing submission $id ($($status.status)) is preserved. Resume only an API-created, never web-edited draft by explicitly supplying its ID. No submission was changed."
    }
} else {
    if ($ResumeSubmissionId) { throw 'The requested resume ID is not the current pending submission.' }
    $created = Request POST "$appUri/submissions"
    $id = [string]$created.id
    if ($id -notmatch '^[0-9]+$') { throw 'The API did not return a valid submission ID.' }
    $subUri = "$appUri/submissions/$id"
    Write-Host "Created API submission $id. If this run fails before commit, resume this ID; do not edit it on the web."
    if ($env:GITHUB_STEP_SUMMARY) { "API draft ID: $id (use resume_submission_id only for this API-created draft)." >> $env:GITHUB_STEP_SUMMARY }
    $sub = Request GET $subUri
}
$uploadUri = Assert-LapdroidUploadUri -Uri $sub.fileUploadUrl
Write-Output "::add-mask::$uploadUri"
$baseListing = @($sub.listings.PSObject.Properties | Where-Object Name -ieq 'en-us')
if ($baseListing.Count -ne 1 -or -not $baseListing[0].Value.baseListing) { throw 'A completed initial en-us listing is required.' }
$base = $baseListing[0].Value.baseListing
foreach ($property in @('description','shortDescription','features')) {
    $base | Add-Member -NotePropertyName $property -NotePropertyValue $listing.$property -Force
}
$base | Add-Member -NotePropertyName releaseNotes -NotePropertyValue $notes -Force
Set-LapdroidListingScreenshots -Submission $sub -Screenshots $shots
$sub.applicationCategory = 'UtilitiesAndTools'
$sub.targetPublishMode = 'Immediate'
if ($sub.packageDeliveryOptions.packageRollout) { $sub.packageDeliveryOptions.packageRollout.isPackageRollout = $false }
if ($sub.PSObject.Properties.Name -contains 'notesForCertification') { $sub.notesForCertification = $listing.certificationNotes }
$packages = @()
foreach ($old in @($sub.applicationPackages)) {
    if ($null -eq $old -or $old.fileStatus -eq 'PendingUpload') { continue }
    $old.fileStatus = 'PendingDelete'; $packages += $old
}
$sub.applicationPackages = @($packages) + @([pscustomobject]@{fileName=$packageName;fileStatus='PendingUpload'})
$null = Request PUT $subUri $sub
# Upload only the files referenced by the metadata, never credentials or logs.
$staging = Join-Path ([IO.Path]::GetTempPath()) ('lapdroid-upload-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging | Out-Null
Copy-Item -LiteralPath (Join-Path $CandidateDirectory $packageName) -Destination $staging
foreach ($shot in $shots) { Copy-Item -LiteralPath $shot.path -Destination $staging }
$zip = "$staging.zip"
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip
try {
    $null = Invoke-WebRequest -Method Put -Uri $uploadUri -Headers @{'x-ms-blob-type'='BlockBlob'} -ContentType 'application/zip' -InFile $zip -TimeoutSec 900
} catch { throw "Package upload for submission $id failed. Signed URL and response details are omitted. No commit was attempted." }
$null = Request POST "$subUri/commit"
for ($attempt=0; $attempt -lt 12; $attempt++) {
    $status = Request GET "$subUri/status"
    Write-Host "Submission $id status: $($status.status)"
    if ($status.status -ne 'CommitStarted') { break }
    Start-Sleep -Seconds 10
}
if ($status.status -in @('CommitFailed','PreProcessingFailed','CertificationFailed','ReleaseFailed','PublishFailed','Canceled')) { throw "Submission $id failed: $($status.status). See Partner Center for certification details." }
$verified = Request GET $subUri
Assert-LapdroidSubmission -Submission $verified -Version $version -AllowPendingUpload:($status.status -eq 'CommitStarted')
Assert-LapdroidListingScreenshots -Submission $verified -Screenshots $shots
$result = "Lapdroid $version submitted as $id. Current status: $($status.status). Only Published means the release is live."
Write-Host $result
if ($env:GITHUB_STEP_SUMMARY) { $result >> $env:GITHUB_STEP_SUMMARY }
