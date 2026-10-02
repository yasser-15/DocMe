<#
.SYNOPSIS
    DocMe monorepo task runner.

.DESCRIPTION
    This is a monorepo with three pubspecs. `flutter build` / `flutter run` only
    work from packages/patient_app, and JAVA_HOME is not set system-wide, so
    every Gradle invocation otherwise needs two manual steps. This script
    handles both.

.EXAMPLE
    .\build.ps1 apk                 # release APK (flutter's default)
    .\build.ps1 apk --debug         # forwarded verbatim to flutter
    .\build.ps1 apk --release       # explicit release
    .\build.ps1 apk --split-per-abi # smaller per-ABI APKs
    .\build.ps1 run                 # launch on the connected device
    .\build.ps1 check               # analyze + test across all three packages
    .\build.ps1 check -Package docme_ui
    .\build.ps1 clean -Package patient_app
    .\build.ps1 db up               # start the containerised database
    .\build.ps1 db migrate          # apply supabase/migrations
    .\build.ps1 db test             # run the RLS verification suite
    .\build.ps1 db psql             # interactive psql inside the network
    .\build.ps1 db reset            # DESTRUCTIVE: drop volume, rebuild, re-migrate
    .\build.ps1 docker build        # build the containerised APK image

.NOTES
    The release build is currently signed with the debug key, because
    android/app/build.gradle.kts still points signingConfig at
    signingConfigs.debug. Replace it before any real distribution.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('apk', 'run', 'check', 'analyze', 'test', 'clean', 'db', 'docker')]
    [string]$Task = 'check',

    # Sub-command for the `db` task.
    [Parameter(Position = 1)]
    [ValidateSet('up', 'down', 'migrate', 'test', 'psql', 'reset', 'logs', 'status')]
    [string]$DbTask = 'up',

    # Which package a task applies to. `apk` and `run` are patient_app only.
    [ValidateSet('all', 'docme_core', 'docme_ui', 'patient_app')]
    [string]$Package = 'all',

    # Env file for the compose project name and ports. Copy .env.example to
    # .env on first use; use a second file to drive a second isolated stack.
    [string]$EnvFile,

    # Any remaining arguments are forwarded to flutter verbatim.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$JdkPath = 'C:\Program Files\Android\Android Studio\jbr'

if (-not $EnvFile) { $EnvFile = Join-Path $RepoRoot '.env' }

# The env file decides the compose project name and the published port, so it is
# the switch that selects which isolated stack you are talking to. Point
# -EnvFile at .env.b (with COMPOSE_PROJECT_NAME=docme-b, POSTGRES_PORT=54330)
# to drive a second copy without disturbing the first.
$Compose = @('compose', '--env-file', $EnvFile, '-f', "$RepoRoot\docker\compose.yaml")

# Resolve the db container id through compose instead of hardcoding
# `docme-db-1`. The generated name depends on the project name, so a hardcoded
# one silently breaks every stack that is not called `docme` — and it fails with
# a confusing empty health string rather than saying "no such container".
#
# Every docker call below is wrapped because $ErrorActionPreference is 'Stop' and
# PowerShell 7.3+ turns a non-zero native exit code into a terminating error. A
# stopped database is an expected state to poll through, not a crash.
function Invoke-DockerQuiet {
    param([string[]]$Arguments)
    $out = ''
    try {
        $out = (& docker @Arguments 2>$null) -join "`n"
    } catch {
        return ''
    }
    if ($LASTEXITCODE -ne 0) { return '' }
    return $out
}

function Get-DbContainerId {
    # Built into a variable first: passing `a + b + c` straight into a command
    # is parsed as a single argument expression, not as a concatenated array.
    $dockerArgs = @('compose') + $Compose + @('ps', '-q', 'db')
    $id = Invoke-DockerQuiet $dockerArgs
    if (-not $id) { return $null }
    return $id.Trim()
}

function Wait-DbHealthy {
    param([int]$TimeoutSec = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $id = Get-DbContainerId
        if ($id) {
            $h = Invoke-DockerQuiet @('inspect', '--format', '{{.State.Health.Status}}', $id)
            if ($h.Trim() -eq 'healthy') { return $true }
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

# All pubspecs in the monorepo, in dependency order.
$AllPackages = @('docme_core', 'docme_ui', 'patient_app')

function Resolve-Targets {
    if ($Package -eq 'all') { return $AllPackages }
    return @($Package)
}

function Invoke-Flutter {
    param([string]$Dir, [string[]]$FlutterArgs)

    Push-Location $Dir
    try {
        Write-Host "==> flutter $($FlutterArgs -join ' ')" -ForegroundColor DarkGray
        & flutter @FlutterArgs
        if ($LASTEXITCODE -ne 0) {
            throw "flutter $($FlutterArgs[0]) failed in $Dir (exit $LASTEXITCODE)"
        }
    }
    finally {
        Pop-Location
    }
}

# Gradle needs JAVA_HOME; Android Studio bundles the JDK we use.
function Set-JavaHome {
    if (-not (Test-Path -LiteralPath $JdkPath)) {
        Write-Warning "JDK not found at $JdkPath - Gradle may fail."
        return
    }
    if ($env:JAVA_HOME -ne $JdkPath) {
        $env:JAVA_HOME = $JdkPath
    }
}

switch ($Task) {
    'apk' {
        Set-JavaHome
        Invoke-Flutter "$RepoRoot\packages\patient_app" (@('build', 'apk') + $Rest)
    }

    'run' {
        Set-JavaHome
        Invoke-Flutter "$RepoRoot\packages\patient_app" (@('run') + $Rest)
    }

    'clean' {
        foreach ($p in (Resolve-Targets)) {
            Invoke-Flutter "$RepoRoot\packages\$p" @('clean')
        }
    }

    'analyze' {
        foreach ($p in (Resolve-Targets)) {
            Invoke-Flutter "$RepoRoot\packages\$p" @('analyze')
        }
    }

    'test' {
        foreach ($p in (Resolve-Targets)) {
            Invoke-Flutter "$RepoRoot\packages\$p" @('test')
        }
    }

    'check' {
        # analyze and test per package so a failure names the culprit package.
        $failed = @()
        foreach ($p in (Resolve-Targets)) {
            $dir = "$RepoRoot\packages\$p"
            Push-Location $dir
            try {
                Write-Host "==> $p : analyze" -ForegroundColor Cyan
                & flutter analyze
                if ($LASTEXITCODE -ne 0) { $failed += "$p (analyze)" }

                Write-Host "==> $p : test" -ForegroundColor Cyan
                & flutter test
                if ($LASTEXITCODE -ne 0) { $failed += "$p (test)" }
            }
            finally {
                Pop-Location
            }
        }

        if ($failed.Count) {
            Write-Host "`nFAILED:" -ForegroundColor Red
            $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
            throw "check failed"
        }

        Write-Host "`nAll packages clean." -ForegroundColor Green
    }

    'db' {
        # Without this, docker compose fails with an opaque
        # `Couldn't find env file` that gives no hint about the fix.
        if (-not (Test-Path -LiteralPath $EnvFile)) {
            throw "env file not found: $EnvFile`nCopy .env.example to .env first (or pass -EnvFile <path>)."
        }

        # The tools profile carries migrate/psql/test. Those are one-shot jobs,
        # not services, so `up` never starts them; they run and exit.
        switch ($DbTask) {
            'up' {
                & docker @Compose up -d db
                if ($LASTEXITCODE -ne 0) { throw 'failed to start the database' }
                Write-Host 'waiting for the database to report healthy...'
                if (-not (Wait-DbHealthy)) { throw 'database did not become healthy' }
                # Bringing the database up without applying migrations leaves a
                # useless empty schema, so chain straight into them.
                & docker @Compose --profile tools run --rm migrate
            }
            'down'    { & docker @Compose down }
            'migrate' { & docker @Compose --profile tools run --rm migrate }
            'test'    { & docker @Compose --profile tools run --rm test }
            'psql'    { & docker @Compose --profile tools run --rm psql }
            'logs'    { & docker @Compose logs -f db }
            'status'  { & docker @Compose ps }
            'reset' {
                Write-Warning 'reset DESTROYS the database volume. All local data is lost.'
                & docker @Compose down -v
                & docker @Compose up -d db
                if (-not (Wait-DbHealthy)) { throw 'database did not become healthy' }
                & docker @Compose --profile tools run --rm migrate
                & docker @Compose --profile tools run --rm test
            }
        }
    }

    'docker' {
        # Containerised build. Reproducible, no host toolchain required.
        & docker build -f "$RepoRoot\docker\ci\Dockerfile" -t docme-build $RepoRoot
        if ($LASTEXITCODE -ne 0) { throw 'failed to build docme-build' }
    }
}