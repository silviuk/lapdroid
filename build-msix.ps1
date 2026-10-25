param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')][string]$Version,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedSha256,
    [string]$MakeAppx = ''
)
$ErrorActionPreference = 'Stop'
$Executable = (Resolve-Path -LiteralPath $Executable).Path
if ((Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash -ine $ExpectedSha256) { throw 'Published executable digest mismatch.' }
$bytes = [IO.File]::ReadAllBytes($Executable)
if ($bytes.Length -lt 256 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { throw 'Not a Windows executable.' }
$pe = [BitConverter]::ToInt32($bytes, 0x3c)
if ($pe -lt 64 -or $pe + 6 -ge $bytes.Length -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664) { throw 'Expected x64 PE executable.' }
if (@($Version.Split('.') | Where-Object { [int]$_ -gt 65535 }).Count) { throw 'MSIX version component out of range.' }
if (-not $MakeAppx) {
    $command = Get-Command MakeAppx.exe -ErrorAction SilentlyContinue
    if ($command) { $MakeAppx = $command.Source }
    else {
        $sdk = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
        $MakeAppx = Get-ChildItem -LiteralPath $sdk -Directory | Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'x64\makeappx.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $MakeAppx) { throw 'Install the Windows SDK for MakeAppx.exe.' }
    }
}
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot 'dist') | Out-Null
$staging = Join-Path $PSScriptRoot ('.build/msix-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging -Force | Out-Null
[xml]$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'store/AppxManifest.xml')
$manifest.Package.Identity.Version = "$Version.0"
$manifest.Save((Join-Path $staging 'AppxManifest.xml'))
Copy-Item -LiteralPath $Executable -Destination (Join-Path $staging 'Lapdroid.exe')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'store/Assets') -Destination $staging -Recurse
foreach ($file in @('README.md','LICENSE','PRIVACY.md')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $staging }
$package = Join-Path $PSScriptRoot "dist/Lapdroid-$Version.0-x64.msix"
& $MakeAppx pack /d $staging /p $package /o
if ($LASTEXITCODE -ne 0) { throw 'MSIX validation/packaging failed.' }
$hash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$package.sha256", "$hash  $([IO.Path]::GetFileName($package))`n")
Write-Output "Store package: $package (unsigned; Store signing occurs after certification)."
