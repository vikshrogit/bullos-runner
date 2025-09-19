<#
.SYNOPSIS
  GitHub Actions self-hosted runner entrypoint for Windows (PowerShell edition)

.EXPECTED ENVIRONMENT VARIABLES
  GITHUB_URL (https://github.com/<org> or https://github.com/<org>/<repo>) - REQUIRED
  RUNNER_TOKEN (short-lived) - auto-generated if GITHUB_PAT provided
  GITHUB_PAT (long-lived PAT) - optional, used to fetch new RUNNER_TOKEN
  RUNNER_VERSION, RUNNER_NAME, RUNNER_LABELS, RUNNER_WORKDIR, RUNNER_RUNNERGROUP
  RUNNER_EPHEMERAL, METRICS_ENABLED, TRACING_ENABLED, AUTOSCALE_MODE
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$homeDir = $env:USERPROFILE
$runnerDir = Join-Path $homeDir "actions-runner"

if (-not $env:GITHUB_URL) {
    throw "ERROR: GITHUB_URL must be set."
}

# Detect arch
$arch = $env:PROCESSOR_ARCHITECTURE
switch ($arch.ToLower()) {
    "amd64" { $rlArch = "x64" }
    "arm64" { $rlArch = "arm64" }
    default { throw "Unsupported arch: $arch" }
}

$downloadUrl = "https://github.com/actions/runner/releases/download/v$($env:RUNNER_VERSION)/actions-runner-win-$rlArch-$($env:RUNNER_VERSION).zip"

# Download runner if missing
if (-not (Test-Path $runnerDir)) {
    New-Item -ItemType Directory -Force -Path $runnerDir | Out-Null
    Write-Host "Downloading runner $($env:RUNNER_VERSION) for $rlArch..."
    $zipFile = Join-Path $env:TEMP "runner.zip"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile
    Expand-Archive -Path $zipFile -DestinationPath $runnerDir -Force
    Remove-Item $zipFile
}

Set-Location $runnerDir

function Get-RunnerToken {
    if (-not $env:GITHUB_PAT) {
        throw "ERROR: RUNNER_TOKEN expired and no GITHUB_PAT provided."
    }

    $apiUrl = "https://api.github.com"
    $urlPath = $env:GITHUB_URL -replace '^https://github.com/', ''

    if ($urlPath -match ".+/.+") {
        $owner, $repo = $urlPath -split '/'
        $tokenUrl = "$apiUrl/repos/$owner/$repo/actions/runners/registration-token"
    } else {
        $owner = $urlPath
        $orgUrl = "$apiUrl/orgs/$owner/actions/runners/registration-token"
        $userUrl = "$apiUrl/users/$owner/actions/runners/registration-token"

        try {
            Invoke-RestMethod -Uri "$apiUrl/orgs/$owner" -Headers @{ Authorization = "token $env:GITHUB_PAT" } | Out-Null
            $tokenUrl = $orgUrl
        } catch {
            $tokenUrl = $userUrl
        }
    }

    Write-Host "Requesting new RUNNER_TOKEN from $tokenUrl..."
    $resp = Invoke-RestMethod -Method Post -Uri $tokenUrl -Headers @{ Authorization = "token $env:GITHUB_PAT" }
    if (-not $resp.token) {
        throw "ERROR: Failed to fetch RUNNER_TOKEN"
    }
    $env:RUNNER_TOKEN = $resp.token
}

# If RUNNER_TOKEN missing, fetch one
if (-not $env:RUNNER_TOKEN) {
    Get-RunnerToken
}

# Cleanup old config
if (Test-Path ".runner") {
    Write-Host "Removing previous runner config..."
    try {
        .\config.cmd remove --unattended --token $env:RUNNER_TOKEN
    } catch { }
    Remove-Item ".runner" -Force -ErrorAction SilentlyContinue
}

function Register-Runner {
    $runnerArgs = @(
        "--unattended",
        "--url", $env:GITHUB_URL,
        "--name", ($(if ($env:RUNNER_NAME) { $env:RUNNER_NAME } else { $env:COMPUTERNAME })),
        "--token", $env:RUNNER_TOKEN,
        "--work", ($(if ($env:RUNNER_WORKDIR) { $env:RUNNER_WORKDIR } else { "_work" }))
    )

    if ($env:RUNNER_LABELS)     { $runnerArgs += @("--labels", $env:RUNNER_LABELS) }
    if ($env:RUNNER_EPHEMERAL)  { $runnerArgs += "--ephemeral" }
    if ($env:RUNNER_RUNNERGROUP){ $runnerArgs += @("--runnergroup", $env:RUNNER_RUNNERGROUP) }

    Write-Host "Configuring runner..."
    & .\config.cmd @runnerArgs
    return $LASTEXITCODE
}

if ((Register-Runner) -ne 0) {
    Write-Host "Runner config failed. Trying to refresh token..."
    Get-RunnerToken
    Register-Runner | Out-Null
}

# Handle SIGTERM equivalent
$cleanup = {
    Write-Host "Stopping runner. Removing configuration..."
    try {
        .\config.cmd remove --unattended --token $env:RUNNER_TOKEN
    } catch { }
    exit 0
}

Register-EngineEvent PowerShell.Exiting -Action $cleanup | Out-Null

# Start runner
if ($args.Count -gt 0 -and $args[0] -eq "run") {
    & .\run.cmd
} else {
    & .\run.cmd @args
}
