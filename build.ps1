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

    # Any remaining arguments are forwarded to flutter verbatim.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$JdkPath = 'C:\Program Files\Android\Android Studio\jbr'
$Compose = @('compose', '--env-file', "$RepoRoot\.env", '-f', "$RepoRoot\docker\compose.yaml")

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
        # The tools profile carries migrate/psql/test. Those are one-shot jobs,
        # not services, so `up` never starts them; they run and exit.
        switch ($DbTask) {
            'up' {
                & docker @Compose up -d db
                if ($LASTEXITCODE -ne 0) { throw 'failed to start the database' }
                Write-Host 'waiting for the database to report healthy...'
                $healthy = $false
                for ($i = 0; $i -lt 40; $i++) {
                    $h = docker inspect --format '{{.State.Health.Status}}' docme-db-1 2>$null
                    if ($h -eq 'healthy') { $healthy = $true; break }
                    Start-Sleep -Seconds 3
                }
                if (-not $healthy) { throw 'database did not become healthy' }
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
                for ($i = 0; $i -lt 40; $i++) {
                    $h = docker inspect --format '{{.State.Health.Status}}' docme-db-1 2>$null
                    if ($h -eq 'healthy') { break }
                    Start-Sleep -Seconds 3
                }
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