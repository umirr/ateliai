param(
    [string]$Flutter = 'flutter',
    [string]$Iscc = 'ISCC.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $projectRoot
try {
    # Run flutter pub get after dependency changes. On hosts without Developer
    # Mode, pre-create local plugin junctions before the --no-pub build.
    $plugins = Get-Content '.flutter-plugins-dependencies' -Raw | ConvertFrom-Json
    $links = Join-Path $projectRoot 'windows\flutter\ephemeral\.plugin_symlinks'
    New-Item -ItemType Directory -Force -Path $links | Out-Null
    foreach ($plugin in $plugins.plugins.windows) {
        $link = Join-Path $links $plugin.name
        if (-not (Test-Path -LiteralPath $link)) {
            New-Item -ItemType Junction -Path $link -Target ([IO.Path]::GetFullPath($plugin.path)) | Out-Null
        }
    }
    # Regenerate native registration after creating junctions. A previous pub
    # get may have resolved packages but stopped before writing C++ registrants.
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter plugin registration failed.' }
    & $Flutter build windows --release --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows build failed.' }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsRoot = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsRoot) { throw 'Visual C++ Build Tools not found.' }
    $redistRoot = Join-Path $vsRoot 'VC\Redist\MSVC'
    $redist = Get-ChildItem -LiteralPath $redistRoot -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    $crt = Join-Path $redist.FullName 'x64\Microsoft.VC143.CRT'
    $bundle = Join-Path $projectRoot 'build\windows\x64\runner\Release'
    Get-ChildItem -LiteralPath $crt -Filter '*.dll' | Copy-Item -Destination $bundle
    & $Iscc (Join-Path $PSScriptRoot 'storyloom.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
    $setup = Join-Path $projectRoot '..\windows\Ateliai-Setup-0.8.3-x64.exe'
    $hash = Get-FileHash -LiteralPath $setup -Algorithm SHA256
    ($hash.Hash + '  ' + [IO.Path]::GetFileName($setup)) |
        Set-Content -LiteralPath ($setup + '.sha256') -Encoding utf8
} finally {
    Pop-Location
}
