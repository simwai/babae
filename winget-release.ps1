<#[
.SYNOPSIS
    Builds, uploads to GitLab Package Registry, and submits/updates winget manifest for babae.

.DESCRIPTION
    This script orchestrates the full release flow for babae to winget:
    1. Determines version automatically from git tags (auto-versioning)
    2. Builds the portable package (delegates to build.ps1)
    3. Uploads the zip to GitLab Generic Package Registry
    4. Submits or updates the winget manifest via wingetcreate

    Requires:
    - GITLAB_TOKEN env var (write_package, write_repository, api scopes)
    - GITHUB_TOKEN env var (repo scope for wingetcreate PR creation)
    - .NET SDK (for wingetcreate auto-install)
    - Git

.NOTES
    Project: babae - Zero-dependency TUI editor
    Package Registry: GitLab (gitlab.com/simwai/babae)
    Manifest Repo: microsoft/winget-pkgs (via wingetcreate)

.PARAMETER Bump
    Version bump type when auto-versioning. Default: patch.
    patch: 0.1.0 -> 0.1.1
    minor: 0.1.0 -> 0.2.0
    major: 0.1.0 -> 1.0.0

.PARAMETER GitLabToken
    GitLab Personal Access Token. Defaults to $env:GITLAB_TOKEN.

.PARAMETER GitHubToken
    GitHub Personal Access Token. Defaults to $env:GITHUB_TOKEN.

.PARAMETER GitLabProject
    GitLab project path. Defaults to "simwai/babae".

.PARAMETER SkipBuild
    Skip the build step (assumes dist/babae-{Version}.zip already exists).

.PARAMETER SkipGitLabUpload
    Skip GitLab Package Registry upload.

.PARAMETER SkipWingetSubmit
    Skip wingetcreate submit/update.

.PARAMETER DryRun
    Print actions without executing any network calls.

.EXAMPLE
    $env:GITLAB_TOKEN = "glpat-xxx"
    $env:GITHUB_TOKEN = "ghp_xxx"
    .\winget-release.ps1

.EXAMPLE
    .\winget-release.ps1 -Bump minor

.EXAMPLE
    .\winget-release.ps1 -DryRun

.EXAMPLE
    .\winget-release.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
    [ValidateSet('patch','minor','major')][string]$Bump = 'patch',
    [string]$GitLabToken = $env:GITLAB_TOKEN,
    [string]$GitHubToken = $env:GITHUB_TOKEN,
    [string]$GitLabProject = "simwai/babae",
    [switch]$SkipBuild,
    [switch]$SkipGitLabUpload,
    [switch]$SkipWingetSubmit,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# --- Helper functions ---

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success([string]$Message) {
    Write-Host "   [OK] $Message" -ForegroundColor Green
}

function Write-Warning([string]$Message) {
    Write-Host "   [WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg([string]$Message) {
    Write-Host "   [ERR] $Message" -ForegroundColor Red
}

function Invoke-DryRunOrReal([string]$Description, [scriptblock]$Action) {
    if ($DryRun) {
        Write-Host "   [DRY-RUN] $Description" -ForegroundColor Magenta
        return $null
    }
    return & $Action
}

function Require-Command([string]$Name, [string]$InstallHint = "") {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        $msg = "Required command not found: $Name"
        if ($InstallHint) { $msg += " - $InstallHint" }
        throw $msg
    }
}

function Get-NextVersion([string]$BumpType) {
    Write-Step "Determining next version from git tags"
    
    $latestTag = git describe --tags --abbrev=0 2>$null
    if (-not $latestTag) {
        Write-Warning "No git tags found, starting at 0.1.0"
        return "0.1.0"
    }
    
    if ($latestTag -notmatch '^v?(\d+)\.(\d+)\.(\d+)$') {
        throw "Latest tag '$latestTag' is not a valid semantic version (expected vX.Y.Z or X.Y.Z)"
    }
    
    $major = [int]$matches[1]
    $minor = [int]$matches[2]
    $patch = [int]$matches[3]
    
    switch ($BumpType) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
    }
    
    $nextVersion = "$major.$minor.$patch"
    Write-Success "Next version: $nextVersion (from tag $latestTag, bump: $BumpType)"
    return $nextVersion
}

function Get-GitLabProjectId([string]$ProjectPath, [string]$Token) {
    $encoded = [System.Web.HttpUtility]::UrlEncode($ProjectPath)
    $url = "https://gitlab.com/api/v4/projects/$encoded"
    $headers = @{ "PRIVATE-TOKEN" = $Token }
    try {
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        return $resp.id
    }
    catch {
        throw "Failed to get GitLab project ID for '$ProjectPath': $($_.Exception.Message)"
    }
}

function Upload-ToGitLabPackageRegistry([string]$ProjectId, [string]$PackageName, [string]$Version, [string]$FilePath, [string]$Token) {
    $fileName = Split-Path $FilePath -Leaf
    $url = "https://gitlab.com/api/v4/projects/$ProjectId/packages/generic/$PackageName/$Version/$fileName"
    $headers = @{ "PRIVATE-TOKEN" = $Token }
    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)

    Write-Host "   Uploading $fileName ($([Math]::Round($fileBytes.Length / 1MB, 2)) MB)..."
    try {
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -InFile $FilePath -ContentType "application/octet-stream"
        $packageUrl = "https://gitlab.com/$GitLabProject/-/package_files/$($resp.package_file_id)/download"
        Write-Success "Uploaded to GitLab Package Registry: $packageUrl"
        return $packageUrl
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 409) {
            Write-Warning "Package file already exists (409 Conflict), continuing..."
            $packageUrl = "https://gitlab.com/$GitLabProject/-/package_files/$Version/$fileName"
            return $packageUrl
        }
        throw "GitLab package upload failed: $($_.Exception.Message)"
    }
}

function Ensure-WingetCreateInstalled() {
    Write-Step "Ensuring wingetcreate is installed"
    if (Get-Command wingetcreate -ErrorAction SilentlyContinue) {
        Write-Success "wingetcreate already installed: $(wingetcreate --version)"
        return
    }
    Write-Host "   Installing wingetcreate via dotnet tool..."
    $result = Invoke-DryRunOrReal "dotnet tool install -g Microsoft.WingetCreate" {
        & dotnet tool install -g Microsoft.WingetCreate
    }
    if (-not $DryRun) {
        $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if (-not (Get-Command wingetcreate -ErrorAction SilentlyContinue)) {
            Write-Warning "wingetcreate installed but not in current PATH. Restart shell or add ~/.dotnet/tools to PATH."
        }
        else {
            Write-Success "wingetcreate installed: $(wingetcreate --version)"
        }
    }
}

function Check-WingetPackageExists([string]$GitHubToken) {
    Write-Step "Checking if winget package exists in microsoft/winget-pkgs"
    $url = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/s/simwai/babae"
    $headers = @{
        "Authorization" = "Bearer $GitHubToken"
        "Accept" = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    try {
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        $exists = $resp | Where-Object { $_.name -match '^\d+\.\d+\.\d+$' }
        if ($exists) {
            Write-Success "Package exists in winget-pkgs (versions: $($exists.name -join ', '))"
            return $true
        }
        Write-Host "   No existing versions found - will submit as new package"
        return $false
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404) {
            Write-Host "   Package directory not found - will submit as new package"
            return $false
        }
        throw "Failed to check winget-pkgs: $($_.Exception.Message)"
    }
}

function Run-WingetCreate([string]$Version, [string]$ManifestDir, [string]$GitHubToken, [bool]$IsUpdate) {
    Write-Step "Running wingetcreate $($IsUpdate ? 'update' : 'submit')"
    $cmd = if ($IsUpdate) {
        "wingetcreate update --version $Version --manifest-dir $ManifestDir --token $GitHubToken --submit"
    }
    else {
        "wingetcreate submit --manifest-dir $ManifestDir --token $GitHubToken"
    }
    Write-Host "   Command: $cmd"
    Invoke-DryRunOrReal $cmd {
        & cmd /c $cmd
        if ($LASTEXITCODE -ne 0) {
            throw "wingetcreate failed with exit code $LASTEXITCODE"
        }
    }
    Write-Success "wingetcreate completed"
}

# --- Validation ---

Write-Step "Validating inputs"
if (-not $GitLabToken) { throw "GITLAB_TOKEN not provided (env var or -GitLabToken)" }
if (-not $GitHubToken) { throw "GITHUB_TOKEN not provided (env var or -GitHubToken)" }

Require-Command "git"
Require-Command "dotnet"
Require-Command "pwsh"

# --- Auto-versioning ---

$Version = Get-NextVersion -BumpType $Bump

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $repoRoot "dist"
$zipPath = Join-Path $distDir "babae-$Version.zip"
$manifestDir = Join-Path $repoRoot "manifests\s\simwai\babae\$Version"

if (-not (Test-Path $manifestDir)) {
    throw "Manifest directory not found: $manifestDir"
}

# --- Build ---

if (-not $SkipBuild) {
    Write-Step "Building package via build.ps1"
    Invoke-DryRunOrReal ".\build.ps1 -Version $Version" {
        & "$repoRoot\build.ps1" -Version $Version
    }
}
else {
    Write-Host "   Skipping build (--SkipBuild)"
}

if (-not (Test-Path $zipPath)) {
    throw "Package zip not found: $zipPath"
}
Write-Success "Package found: $zipPath"

# --- Upload to GitLab Package Registry ---

$packageUrl = $null
if (-not $SkipGitLabUpload) {
    Write-Step "Uploading to GitLab Package Registry"
    $projectId = Invoke-DryRunOrReal "Get GitLab project ID" { Get-GitLabProjectId $GitLabProject $GitLabToken }
    if (-not $DryRun) {
        $packageUrl = Upload-ToGitLabPackageRegistry $projectId "babae" $Version $zipPath $GitLabToken
    }
}
else {
    Write-Host "   Skipping GitLab upload (--SkipGitLabUpload)"
    $packageUrl = "https://gitlab.com/$GitLabProject/-/package_files/$Version/babae-$Version.zip"
}

# --- Verify installer manifest SHA256 ---

Write-Step "Verifying installer manifest SHA256"
$installerManifest = Join-Path $manifestDir "simwai.babae.installer.yaml"
if (Test-Path $installerManifest) {
    $content = Get-Content $installerManifest -Raw
    $sha256 = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToUpper()
    if ($content -match "InstallerSha256: $sha256") {
        Write-Success "Manifest SHA256 matches package: $sha256"
    }
    else {
        Write-Warning "Manifest SHA256 mismatch! Expected: $sha256"
        if (-not $DryRun) {
            $updated = $content -replace 'InstallerSha256: [0-9A-Fa-f]{64}', "InstallerSha256: $sha256"
            Set-Content $installerManifest -Value $updated -NoNewline -Encoding UTF8
            Write-Success "Updated installer manifest with correct SHA256"
        }
    }
}
else {
    Write-Warning "Installer manifest not found: $installerManifest"
}

# --- wingetcreate submit/update ---

if (-not $SkipWingetSubmit) {
    Ensure-WingetCreateInstalled
    $exists = Invoke-DryRunOrReal "Check winget-pkgs for existing package" { Check-WingetPackageExists $GitHubToken }
    $isUpdate = $exists -eq $true
    Invoke-DryRunOrReal "Run wingetcreate" { Run-WingetCreate $Version $manifestDir $GitHubToken $isUpdate }
}
else {
    Write-Host "   Skipping wingetcreate (--SkipWingetSubmit)"
}

# --- Summary ---

Write-Step "Release Summary"
Write-Host "Version: $Version"
Write-Host "Package: $packageUrl"
Write-Host "Manifest: $manifestDir"
if (-not $SkipWingetSubmit) {
    Write-Host "wingetcreate: $($isUpdate ? 'update (PR to existing)' : 'submit (new package PR)')"
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Monitor wingetcreate PR at: https://github.com/microsoft/winget-pkgs/pulls"
Write-Host "2. After merge, users can install with: winget install simwai.babae"
Write-Host "3. Verify installation: winget show simwai.babae"