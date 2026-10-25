param([Parameter(Mandatory)][string]$ReleaseTag)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/StorePublishing.ps1"
if ($env:GH_REPO -cne 'silviuk/lapdroid') { throw 'Release source must be silviuk/lapdroid.' }
if ($ReleaseTag -cnotmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?$') { throw 'Use an exact stable vMAJOR.MINOR or vMAJOR.MINOR.PATCH release tag.' }
$version = $ReleaseTag.Substring(1)
if ($version.Split('.').Count -eq 2) { $version += '.0' }
$root = Split-Path $PSScriptRoot -Parent
$release = gh release view $ReleaseTag --repo $env:GH_REPO --json tagName,isDraft,isPrerelease,assets,body | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $release.tagName -cne $ReleaseTag -or $release.isDraft -or $release.isPrerelease) { throw 'Select a published stable release.' }
$asset = @($release.assets | Where-Object name -ceq 'Lapdroid.exe')
if ($asset.Count -ne 1 -or $asset[0].digest -cnotmatch '^sha256:[a-f0-9]{64}$' -or $asset[0].url -cne "https://github.com/$env:GH_REPO/releases/download/$ReleaseTag/Lapdroid.exe") { throw 'A single published Lapdroid.exe with a GitHub SHA256 digest is required.' }
$digest = $asset[0].digest.Substring(7)
$sha = gh api "repos/$env:GH_REPO/commits/$ReleaseTag" --jq .sha
if ($LASTEXITCODE -ne 0 -or $sha -cnotmatch '^[a-f0-9]{40}$') { throw 'Cannot resolve the release tag.' }
$download = Join-Path $root ('.build/download-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $download -Force | Out-Null
gh release download $ReleaseTag --repo $env:GH_REPO --pattern Lapdroid.exe --dir $download
if ($LASTEXITCODE -ne 0) { throw 'Release asset download failed.' }
& "$root/build-msix.ps1" -Executable (Join-Path $download 'Lapdroid.exe') -Version $version -ExpectedSha256 $digest
$candidateDirectory = Join-Path $root '.build/store-candidate'
if (Test-Path -LiteralPath $candidateDirectory) { throw 'Candidate directory already exists; use a clean workspace.' }
New-Item -ItemType Directory -Path $candidateDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $root "dist/Lapdroid-$version.0-x64.msix") -Destination $candidateDirectory
Copy-Item -LiteralPath (Join-Path $root 'store/listing-en-US.json') -Destination $candidateDirectory
$null = Get-LapdroidStoreScreenshots -Directory (Join-Path $root 'store/Screenshots') -Version $version
Copy-Item -Path (Join-Path $root 'store/Screenshots/*') -Destination $candidateDirectory
$notes = Get-LapdroidReleaseNotes -Changelog ("# Lapdroid $version`n`n" + $release.body) -Version $version
[IO.File]::WriteAllText((Join-Path $candidateDirectory 'release-notes.txt'),$notes)
$files = @(Get-ChildItem -LiteralPath $candidateDirectory -File | ForEach-Object { @{fileName=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} })
@{productId='9N1L1QZJNT6Z';releaseTag=$ReleaseTag;version=$version;sourceSha=$sha;executableSha256=$digest;files=$files} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $candidateDirectory 'candidate.json') -Encoding utf8
$null = Assert-LapdroidCandidate -Directory $candidateDirectory
if ($env:GITHUB_STEP_SUMMARY) { "Verified $ReleaseTag executable SHA256: $digest. Packaged as $version.0 for 9N1L1QZJNT6Z. Only Published means live." >> $env:GITHUB_STEP_SUMMARY }
