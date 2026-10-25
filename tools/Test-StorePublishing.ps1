$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/StorePublishing.ps1"
function Must-Throw([scriptblock]$Action, [string]$Name) {
    $threw = $false; try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw "Expected rejection: $Name" }; Write-Host "PASS: $Name"
}
function Submission([string]$Version='0.3.0.0') {
    [pscustomobject]@{id='200';applicationCategory='UtilitiesAndTools';targetPublishMode='Immediate';
        applicationPackages=@([pscustomobject]@{fileName='Lapdroid-0.3.0.0-x64.msix';version=$Version;architecture='x64';fileStatus='Uploaded'});
        packageDeliveryOptions=[pscustomobject]@{packageRollout=[pscustomobject]@{isPackageRollout=$false}}}
}
Assert-LapdroidSubmission -Submission (Submission) -Version '0.3.0'
Must-Throw { Assert-LapdroidSubmission -Submission (Submission '0.2.0.0') -Version '0.3.0' } 'older packages rejected'
$sub = Submission; $sub.targetPublishMode='Manual'
Must-Throw { Assert-LapdroidSubmission $sub '0.3.0' } 'held publication rejected'
$sub = Submission; $sub.applicationCategory='Games'
Must-Throw { Assert-LapdroidSubmission $sub '0.3.0' } 'wrong category rejected'
foreach ($status in 'CommitStarted','PreProcessing','Certification','Release','PendingPublication','Publishing','Published') {
    if ((Get-LapdroidSubmissionAction $status) -ne 'Verify') { throw 'Committed submission must not be edited.' }
}
Must-Throw { Get-LapdroidSubmissionAction 'Unexpected' } 'unknown lifecycle states rejected'
Must-Throw { Assert-LapdroidApiBootstrap ([pscustomobject]@{id='9N1L1QZJNT6Z'}) } 'initial web draft is not silently overwritten'
Must-Throw { Assert-LapdroidApiBootstrap ([pscustomobject]@{id='another-app';lastPublishedApplicationSubmission=@{id='100'}}) } 'wrong Store product rejected'
Assert-LapdroidApiBootstrap ([pscustomobject]@{id='9N1L1QZJNT6Z';lastPublishedApplicationSubmission=@{id='100'}})
foreach ($uri in @('http://safe.blob.core.windows.net/a?sig=test','https://evil.example/a?sig=test','https://safe.blob.core.windows.net.evil.example/a?sig=test','https://safe.blob.core.windows.net:444/a?sig=test','https://user@safe.blob.core.windows.net/a?sig=test')) {
    Must-Throw { Assert-LapdroidUploadUri $uri } 'unsafe upload URL rejected'
}
$null = Assert-LapdroidUploadUri 'https://safe.blob.core.windows.net/a?sig=test'
Must-Throw { Get-LapdroidReleaseNotes '# Lapdroid 0.2.0' '0.3.0' } 'notes for another release rejected'
$root = Split-Path $PSScriptRoot
$fixture = Join-Path $root ('.build/store-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
Copy-Item -LiteralPath "$root/store/Screenshots/controls.png","$root/store/Screenshots/diagnostics.png","$root/store/Screenshots/screenshots.json","$root/store/listing-en-US.json" -Destination $fixture
Set-Content -LiteralPath "$fixture/release-notes.txt" -Value "# Lapdroid 0.3.0`n`n- Test release."
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open("$fixture/Lapdroid-0.3.0.0-x64.msix", [IO.Compression.ZipArchiveMode]::Create)
try {
    $writer = [IO.StreamWriter]::new($zip.CreateEntry('AppxManifest.xml').Open())
    try { $writer.Write('<Package><Identity Name="SilviuVlasceanu.Lapdroid" Publisher="CN=FCAD1026-DA23-45D7-835A-3FF4ADD435D4" Version="0.3.0.0" ProcessorArchitecture="x64"/><Applications><Application Executable="Lapdroid.exe"/></Applications></Package>') } finally { $writer.Dispose() }
    $stream = $zip.CreateEntry('Lapdroid.exe').Open()
    try { $stream.Write([byte[]](1,2,3)) } finally { $stream.Dispose() }
} finally { $zip.Dispose() }
$files = @(Get-ChildItem $fixture -File | ForEach-Object { @{fileName=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()} })
$candidate = @{releaseTag='v0.3';version='0.3.0';sourceSha=('a'*40);productId='9N1L1QZJNT6Z';executableSha256='039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';files=$files}
$candidate | ConvertTo-Json -Depth 6 | Set-Content "$fixture/candidate.json"
$null = Assert-LapdroidCandidate $fixture
$candidate.executableSha256 = 'b'*64; $candidate | ConvertTo-Json -Depth 6 | Set-Content "$fixture/candidate.json"
Must-Throw { Assert-LapdroidCandidate $fixture } 'packaged executable must match release digest'
$candidate.executableSha256='039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81'
$candidate | ConvertTo-Json -Depth 6 | Set-Content "$fixture/candidate.json"
Must-Throw { Get-LapdroidPackageIdentity "$fixture/Lapdroid-0.3.0.0-x64.msix" '0.3.1' } 'embedded package version verified'
Add-Content "$fixture/controls.png" 'modified'
Must-Throw { Assert-LapdroidCandidate $fixture } 'modified artifact rejected'
Copy-Item -LiteralPath "$root/store/Screenshots/controls.png" -Destination "$fixture/controls.png"
$candidate.files[0].fileName='../outside.png'; $candidate | ConvertTo-Json -Depth 6 | Set-Content "$fixture/candidate.json"
Must-Throw { Assert-LapdroidCandidate $fixture } 'candidate path traversal rejected'
$candidate.files=$files = @(Get-ChildItem $fixture -File | Where-Object Name -ne 'candidate.json' | ForEach-Object { @{fileName=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()} })
$candidate | ConvertTo-Json -Depth 6 | Set-Content "$fixture/candidate.json"
$null = Assert-LapdroidCandidate $fixture

# Exercise the real submission script with a fake HTTP boundary: no credentials
# or network are used. Verify that failures cannot reach the commit endpoint.
$global:dsStoreMock = @{posts=0;commits=0;hasBaseline=$true;pending=$false;uploadFails=$false;status='None';sub=$null}
function Invoke-RestMethod {
    param($Method,$Uri,$Headers,$ContentType,$Body,$ErrorAction)
    $mock = $global:dsStoreMock
    if ($Uri -like 'https://login.microsoftonline.com/*') { return @{access_token='TEST_TOKEN_NOT_A_CREDENTIAL'} }
    if ($Method -eq 'Get' -and $Uri -match '/applications/9N1L1QZJNT6Z$') {
        return @{id='9N1L1QZJNT6Z';lastPublishedApplicationSubmission=if($mock.hasBaseline){@{id='100'}}else{$null};pendingApplicationSubmission=if($mock.pending){@{id='200'}}else{$null}}
    }
    if ($Uri -match '/status$') { return @{status=$mock.status} }
    if ($Method -eq 'Post' -and $Uri -match '/submissions$') {
        $mock.posts++; $mock.pending=$true
        $mock.sub=[pscustomobject]@{id='200';applicationCategory='UtilitiesAndTools';targetPublishMode='Manual';fileUploadUrl='https://safe.blob.core.windows.net/test?sig=test';applicationPackages=@();packageDeliveryOptions=@{};listings=[pscustomobject]@{'en-us'=[pscustomobject]@{baseListing=[pscustomobject]@{images=@()}}}}
        return @{id='200'}
    }
    if ($Method -eq 'Put') { $mock.sub=$Body | ConvertFrom-Json;return $mock.sub }
    if ($Method -eq 'Post' -and $Uri -match '/commit$') {
        $mock.commits++; $mock.status='Certification';$pkg=$mock.sub.applicationPackages[-1]
        $pkg | Add-Member -NotePropertyName version -NotePropertyValue '0.3.0.0' -Force
        $pkg | Add-Member -NotePropertyName architecture -NotePropertyValue 'x64' -Force
        $pkg.fileStatus='Uploaded';foreach($image in $mock.sub.listings.'en-us'.baseListing.images){$image.fileStatus='Uploaded'}
        return @{status='CommitStarted'}
    }
    if ($Method -eq 'Get' -and $Uri -match '/submissions/200$') { return $mock.sub }
    throw "Unexpected mock API call: $Method $Uri"
}
function Invoke-WebRequest {
    param($Method,$Uri,$Headers,$ContentType,$InFile,$TimeoutSec)
    if ($global:dsStoreMock.uploadFails) { throw 'Injected upload failure' }
    if (-not (Test-Path -LiteralPath $InFile)) { throw 'No upload ZIP' }
    $bundle = [IO.Compression.ZipFile]::OpenRead($InFile)
    try { if ($bundle.Entries.Count -ne 3) { throw 'Bundle must contain only the MSIX and two screenshots.' } } finally { $bundle.Dispose() }
}
$savedEnvironment = @{}
foreach ($name in @('MS_STORE_TENANT_ID','MS_STORE_CLIENT_ID','MS_STORE_CLIENT_SECRET','GITHUB_STEP_SUMMARY')) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name) }
Remove-Item Env:GITHUB_STEP_SUMMARY -ErrorAction SilentlyContinue
$env:MS_STORE_TENANT_ID='00000000-0000-0000-0000-000000000000';$env:MS_STORE_CLIENT_ID=$env:MS_STORE_TENANT_ID;$env:MS_STORE_CLIENT_SECRET='TEST_NOT_A_SECRET'
try {
    $global:dsStoreMock.hasBaseline=$false
    Must-Throw { & "$PSScriptRoot/Submit-Store.ps1" -CandidateDirectory $fixture } 'missing first submission stops before mutation'
    if ($global:dsStoreMock.posts -or $global:dsStoreMock.commits) { throw 'Unexpected mutation without bootstrap' }
    $global:dsStoreMock.hasBaseline=$true;$global:dsStoreMock.uploadFails=$true
    Must-Throw { & "$PSScriptRoot/Submit-Store.ps1" -CandidateDirectory $fixture } 'failed upload never commits'
    if ($global:dsStoreMock.commits -ne 0) { throw 'Failed upload committed' }
    Must-Throw { & "$PSScriptRoot/Submit-Store.ps1" -CandidateDirectory $fixture } 'existing draft requires explicit resume'
    $global:dsStoreMock.uploadFails=$false
    & "$PSScriptRoot/Submit-Store.ps1" -CandidateDirectory $fixture -ResumeSubmissionId '200'
    if ($global:dsStoreMock.commits -ne 1) { throw 'Expected one successful commit' }
    & "$PSScriptRoot/Submit-Store.ps1" -CandidateDirectory $fixture
    if ($global:dsStoreMock.commits -ne 1) { throw 'Committed submission was submitted twice' }
    Write-Host 'PASS: API upload/commit, explicit resume, idempotent certification verification; no network used.'
} finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
    Remove-Item Function:Invoke-RestMethod,Function:Invoke-WebRequest -ErrorAction SilentlyContinue
    Remove-Variable dsStoreMock -Scope Global
}
