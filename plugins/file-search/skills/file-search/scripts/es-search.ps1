#requires -Version 5
<#
.SYNOPSIS
  Robust wrapper around es.exe (the Everything command-line search).

  Two things it does that a bare `es.exe` call does not:

  1. Ensures Everything is actually running. `es.exe` exits with code 8 and
     prints "Everything IPC window not found, IPC unavailable." when the
     Everything index process is down. This wrapper detects that, starts
     Everything, and polls until the index is ready — under a hard time budget,
     so a cold start on huge volumes can't hang the caller (see the recovery
     block for why that matters).

  2. Injects a default result cap (-n 100) when the caller passes no limit.
     An unbounded query like `*.rs` can match hundreds of thousands of files;
     the search itself is instant but streaming that many lines back is what
     makes it feel slow (12s+ in practice). A default cap keeps output usable
     while staying fully overridable — pass your own -n / -max-results / an
     -export-* flag and the wrapper stays out of the way.

.PARAMETER EsArgs
  Everything query and any es.exe flags, forwarded verbatim.

.NOTES
  Env override: ES_SEARCH_RECOVERY_BUDGET_SEC caps how long recovery waits for a
  cold index to build before returning with a "still building, retry" message
  (default 120).

.EXAMPLE
  ./es-search.ps1 -n 20 ext:flac warp
.EXAMPLE
  ./es-search.ps1 -path "S:\projects\djtool" Cargo.toml
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$EsArgs = @()
)

$ErrorActionPreference = 'Stop'

function Find-EverythingExe {
    $candidates = @(
        "$env:ProgramFiles\Everything\Everything.exe",
        "${env:ProgramFiles(x86)}\Everything\Everything.exe",
        "$env:LOCALAPPDATA\Programs\Everything\Everything.exe"
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    $cmd = Get-Command Everything.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Start-Everything {
    $started = $false
    # Prefer the Windows service if installed: it indexes headlessly as SYSTEM
    # and survives across user sessions.
    $svc = Get-Service -Name 'Everything*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($svc) {
        if ($svc.Status -ne 'Running') {
            try { Start-Service $svc.Name; $started = $true } catch { }
        } else {
            $started = $true
        }
    }
    # The service alone does NOT expose an IPC window to a user-session es.exe —
    # es connects to the tray/GUI instance running in the caller's session. So a
    # client process is still required. Launch it minimized to the tray, no
    # window, via -startup.
    $exe = Find-EverythingExe
    if ($exe) {
        Start-Process -FilePath $exe -ArgumentList '-startup' | Out-Null
        $started = $true
    }
    if (-not $started) {
        throw "Everything is not running and could not be started (Everything.exe not found and no service). Install it from https://www.voidtools.com/."
    }
}

function Invoke-EsCapped {
    <#
      Run es.exe with a hard wall-clock cap, killing it if it overruns. Needed
      because during an active index build es blocks until the build finishes and
      does NOT honor its own -timeout — so bounding recovery requires killing the
      process ourselves. Uses the .NET process API with an argument LIST (not a
      quoted string) so Everything query syntax (* ; > | etc.) passes through
      untouched. Returns @{ Out; Code; TimedOut }.
    #>
    param([string[]]$Arguments, [int]$TimeoutMs)

    $esPath = (Get-Command es.exe).Source
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $esPath
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    if ($psi.PSObject.Properties.Name -contains 'ArgumentList') {
        foreach ($a in $Arguments) { [void]$psi.ArgumentList.Add([string]$a) }
    } else {
        # Windows PowerShell 5.1 fallback: quote args that contain spaces.
        $psi.Arguments = ($Arguments | ForEach-Object {
            if ($_ -match '\s') { '"' + $_ + '"' } else { "$_" }
        }) -join ' '
    }

    $p = [System.Diagnostics.Process]::new()
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEndAsync()
    if ($p.WaitForExit($TimeoutMs)) {
        return @{ Out = $stdout.GetAwaiter().GetResult(); Code = $p.ExitCode; TimedOut = $false }
    }
    try { $p.Kill() } catch { }
    return @{ Out = $null; Code = $null; TimedOut = $true }
}

# --- locate es.exe -----------------------------------------------------------
$esCmd = Get-Command es.exe -ErrorAction SilentlyContinue
if (-not $esCmd) {
    throw "es.exe not found on PATH. Install the Everything command-line interface (es) from https://www.voidtools.com/downloads/ (or 'choco install es')."
}

# --- inject a default result cap when the caller gave no limit ---------------
$hasLimit  = $EsArgs | Where-Object { $_ -match '^[-/](n|max-results)$' }
$hasExport = $EsArgs | Where-Object { $_ -match '^[-/]export-' }
$effectiveArgs = @()
if (-not $hasLimit -and -not $hasExport) {
    $effectiveArgs += @('-n', '100')
}
$effectiveArgs += $EsArgs

# --- fast path: Everything is already running --------------------------------
$out  = & es.exe @effectiveArgs 2>&1
$code = $LASTEXITCODE

# --- recover from "Everything not running" (exit code 8) ----------------------
if ($code -eq 8) {
    Write-Host "Everything is not running — starting it and waiting for the index..." -ForegroundColor Yellow
    Start-Everything

    # Why this is a poll-with-hard-cap and not a single long es call:
    #
    # On a cold start Everything rescans every NTFS volume before it can answer
    # anything. On large drives that took up to ~6 MINUTES in testing, and es
    # blocks that entire time — it ignores its own -timeout during an active
    # build. A plain `es -timeout N` therefore either hangs for minutes or (if it
    # ever gives up) tempts a retry that doubles the wait.
    #
    # Instead: start Everything, then probe with SHORT hard-capped es calls
    # (killed if they overrun). Each probe either returns results the instant the
    # index is ready, returns a fast exit 8 (IPC window not up yet — retry), or
    # gets killed mid-build (retry). The whole thing is bounded by a wall-clock
    # budget, so the worst case is "return promptly with a retry hint", never a
    # multi-minute hang.
    $budgetSec = 120
    if ($env:ES_SEARCH_RECOVERY_BUDGET_SEC) {
        [int]::TryParse($env:ES_SEARCH_RECOVERY_BUDGET_SEC, [ref]$budgetSec) | Out-Null
    }

    $recover = [System.Diagnostics.Stopwatch]::StartNew()
    $ready = $false
    while ($recover.Elapsed.TotalSeconds -lt $budgetSec) {
        $probe = Invoke-EsCapped -Arguments $effectiveArgs -TimeoutMs 6000
        if (-not $probe.TimedOut -and $probe.Code -ne 8) {
            $out = $probe.Out; $code = $probe.Code; $ready = $true; break
        }
        Start-Sleep -Milliseconds 500
    }

    if (-not $ready) {
        Write-Host ("Everything has been started and is building its index (large volumes can take several minutes). " +
                    "Waited {0:n0}s; re-run the search shortly." -f $recover.Elapsed.TotalSeconds) -ForegroundColor Red
        $out  = $null
        $code = 8
    }
}

if ($null -ne $out) { $out }
exit $code
