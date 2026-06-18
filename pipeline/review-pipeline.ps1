<#
.SYNOPSIS
  Automated PR code-review pipeline driven by Claude Code (non-interactive).

.DESCRIPTION
  Simulates the review step of a CI/CD pipeline:

    1. Figures out which files the PR changed (git diff base...head).
    2. PER-FILE pass  : reviews each file in isolation for local defects.
    3. CROSS-FILE pass: reviews the whole change-set for contract breaks that
                        only show up across files (skipped with -SinglePass).
    4. Aggregates findings into findings/findings.json + findings/report.md.
    5. Exits non-zero if anything at or above -FailOn severity is found, so the
       build can fail the PR.

  Every model call uses `claude -p` (print mode): Claude does the job and exits.
  Nothing waits for human input, so the pipeline never hangs. Each call is a
  fresh, independent reviewer instance with no memory of writing the code.

.EXAMPLE
  pwsh -File pipeline/review-pipeline.ps1 -Mock
  pwsh -File pipeline/review-pipeline.ps1 -BaseRef main -HeadRef HEAD
  pwsh -File pipeline/review-pipeline.ps1 -ComparePasses -Mock
  pwsh -File pipeline/review-pipeline.ps1 -SinglePass -FailOn critical
#>
[CmdletBinding()]
param(
  [string]   $BaseRef       = 'main',
  [string]   $HeadRef       = 'HEAD',
  [string[]] $Files,                              # explicit file list overrides git diff
  [string]   $Pattern       = '\.js$',            # which changed files to review
  [string]   $OutDir        = 'findings',
  [ValidateSet('critical','high','medium','low','none')]
  [string]   $FailOn        = 'high',
  [switch]   $Mock,                               # use canned reviewer output (no API calls)
  [switch]   $SinglePass,                         # per-file only; skip the cross-file pass
  [switch]   $ComparePasses,                      # print a per-file vs cross-file comparison
  [int]      $MaxFiles      = 200
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$PromptDir = Join-Path $PSScriptRoot 'prompts'
$Rank = @{ critical = 4; high = 3; medium = 2; low = 1 }

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host $msg -ForegroundColor DarkGray }

# --- Resolve a finding's 1-based line number by locating `match` in the file. ---
function Resolve-Line {
  param([string]$AbsPath, [string]$Match)
  if (-not $Match -or -not (Test-Path $AbsPath)) { return 0 }
  $lines = Get-Content -LiteralPath $AbsPath -Encoding UTF8
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Contains($Match)) { return $i + 1 }
  }
  return 0
}

# --- Turn raw model text into an array of finding objects (robust to fences/prose). ---
function ConvertFrom-ReviewerJson {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
  $t = $Text.Trim()
  # Strip ```json / ``` fences if the model added them.
  $t = [regex]::Replace($t, '(?s)^```[a-zA-Z]*\s*', '')
  $t = [regex]::Replace($t, '(?s)\s*```$', '')
  # Extract the outermost [ ... ] array if there is surrounding prose.
  $start = $t.IndexOf('['); $end = $t.LastIndexOf(']')
  if ($start -ge 0 -and $end -gt $start) { $t = $t.Substring($start, $end - $start + 1) }
  try {
    $parsed = $t | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    return @($parsed)
  } catch {
    Write-Warning "Could not parse reviewer output as JSON; treating as no findings."
    return @()
  }
}

# --- Call a fresh Claude reviewer instance in print mode, return parsed findings. ---
function Invoke-Reviewer {
  param([string]$PromptPath, [string]$Stdin)
  $instructions = Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8
  # -p = print mode: non-interactive, prints result and exits (never hangs in CI).
  $raw = $Stdin | claude -p $instructions
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "claude exited with code $LASTEXITCODE; recording no findings for this call."
    return @()
  }
  return ConvertFrom-ReviewerJson ($raw -join "`n")
}

# --- Mock reviewer: read canned findings, resolve line numbers by match. ---
$script:Mockdata = $null
function Get-MockFindings {
  param([string]$Kind, [string]$RelPath, [string]$AbsPath)
  if ($null -eq $script:Mockdata) {
    $script:Mockdata = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mock-findings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  }
  $out = @()
  if ($Kind -eq 'per-file') {
    $list = $script:Mockdata.perFile.$RelPath
    if ($null -eq $list) { return @() }
    foreach ($f in @($list)) {
      $out += [pscustomobject]@{
        file = $RelPath; line = (Resolve-Line $AbsPath $f.match)
        severity = $f.severity; issue = $f.issue; suggested_fix = $f.suggested_fix
      }
    }
  } else {
    foreach ($f in @($script:Mockdata.crossFile)) {
      $abs = Join-Path $RepoRoot $f.file
      $out += [pscustomobject]@{
        file = $f.file; line = (Resolve-Line $abs $f.match)
        severity = $f.severity; issue = $f.issue; suggested_fix = $f.suggested_fix
      }
    }
  }
  return $out
}

# --- Discover the files this PR touched. ---
function Get-ChangedFiles {
  if ($Files) { return $Files }
  $range = "$BaseRef...$HeadRef"
  $diff = git -C $RepoRoot diff --name-only $range 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $diff) {
    Write-Warning "git diff '$range' returned nothing; falling back to tracked files under src/."
    $diff = git -C $RepoRoot ls-files 'src/*'
  }
  return @($diff | Where-Object { $_ -match $Pattern } | Select-Object -First $MaxFiles)
}

# --- Render a human-readable Markdown report (PR-comment friendly). ---
function Write-ReportMarkdown {
  param($Findings, $Changed, [string]$OutPath, $Payload)
  $c = $Payload.counts
  $lines = @()
  $lines += "# Automated code review"
  $lines += ""
  $lines += "Range ``$($Payload.base)...$($Payload.head)`` | $($Payload.files_reviewed) files reviewed | generated $($Payload.generated)"
  $lines += ""
  $lines += "**critical $($c.critical) | high $($c.high) | medium $($c.medium) | low $($c.low) | total $($c.total)**"
  $lines += ""
  if (@($Findings).Count -eq 0) {
    $lines += "No real issues found. Cosmetic/style items are intentionally skipped (see CLAUDE.md)."
  } else {
    foreach ($pass in @('per-file','cross-file')) {
      $group = @($Findings | Where-Object pass -eq $pass)
      if ($group.Count -eq 0) { continue }
      $title = if ($pass -eq 'per-file') { 'Per-file findings (local defects)' } else { 'Cross-file findings (contract breaks across files)' }
      $lines += "## $title"
      $lines += ""
      foreach ($f in ($group | Sort-Object @{e={$Rank[$_.severity]};Descending=$true}, file)) {
        $lines += ("- **[$($f.severity.ToUpper())]** ``$($f.file):$($f.line)`` - $($f.issue)")
        $lines += ("  - Fix: $($f.suggested_fix)")
      }
      $lines += ""
    }
  }
  ($lines -join "`n") | Set-Content -LiteralPath $OutPath -Encoding UTF8
}

# =====================  MAIN  =====================
Push-Location $RepoRoot
try {
  Write-Step "PR review pipeline  (mode: $(if($Mock){'MOCK'}else{'live claude -p'}))"
  $changed = Get-ChangedFiles
  if (-not $changed -or $changed.Count -eq 0) { Write-Warning "No changed files to review."; exit 0 }
  Write-Info ("Reviewing {0} changed file(s): {1}...{2}" -f $changed.Count, $BaseRef, $HeadRef)
  $changed | ForEach-Object { Write-Info "  - $_" }

  $perFile   = @()
  $crossFile = @()

  # ---------- PASS 1: per-file ----------
  Write-Step "Pass 1 - per-file review ($($changed.Count) independent reviewer runs)"
  foreach ($rel in $changed) {
    $abs = Join-Path $RepoRoot $rel
    if (-not (Test-Path $abs)) { continue }
    Write-Host ("  reviewing {0,-22}" -f $rel) -NoNewline
    if ($Mock) {
      $found = Get-MockFindings 'per-file' $rel $abs
    } else {
      $content = Get-Content -LiteralPath $abs -Raw -Encoding UTF8
      $stdin = "FILE: $rel`n`n$content"
      $found = Invoke-Reviewer (Join-Path $PromptDir 'per-file.md') $stdin
    }
    foreach ($f in $found) { $f | Add-Member -NotePropertyName pass -NotePropertyValue 'per-file' -Force }
    $perFile += $found
    $n = @($found).Count
    Write-Host (" {0}" -f $(if($n -eq 0){'clean'}else{"$n finding(s)"})) -ForegroundColor $(if($n -eq 0){'Green'}else{'Yellow'})
  }

  # ---------- PASS 2: cross-file ----------
  if (-not $SinglePass) {
    Write-Step "Pass 2 - cross-file review (1 reviewer run over the whole change-set)"
    if ($Mock) {
      # The cross-file pass only sees the files in scope, so a finding is only
      # reportable when its file is actually part of this change-set.
      $crossFile = @(Get-MockFindings 'cross-file' $null $null | Where-Object { $changed -contains $_.file })
    } else {
      $sb = New-Object System.Text.StringBuilder
      foreach ($rel in $changed) {
        $abs = Join-Path $RepoRoot $rel
        if (-not (Test-Path $abs)) { continue }
        [void]$sb.AppendLine("=== FILE: $rel ===")
        [void]$sb.AppendLine((Get-Content -LiteralPath $abs -Raw -Encoding UTF8))
        [void]$sb.AppendLine("")
      }
      $crossFile = Invoke-Reviewer (Join-Path $PromptDir 'cross-file.md') $sb.ToString()
    }
    foreach ($f in $crossFile) { $f | Add-Member -NotePropertyName pass -NotePropertyValue 'cross-file' -Force }
    Write-Host ("  {0} cross-file contract issue(s)" -f @($crossFile).Count) -ForegroundColor $(if(@($crossFile).Count -eq 0){'Green'}else{'Yellow'})
  } else {
    Write-Info "`n(-SinglePass set: cross-file pass skipped.)"
  }

  $all = @($perFile) + @($crossFile)

  # ---------- Aggregate & write reports ----------
  $outAbs = Join-Path $RepoRoot $OutDir
  if (-not (Test-Path $outAbs)) { New-Item -ItemType Directory -Path $outAbs | Out-Null }
  $jsonPath = Join-Path $outAbs 'findings.json'
  $mdPath   = Join-Path $outAbs 'report.md'

  $payload = [pscustomobject]@{
    base = $BaseRef; head = $HeadRef
    generated = (Get-Date).ToString('s')
    files_reviewed = $changed.Count
    counts = [pscustomobject]@{
      critical = @($all | Where-Object severity -eq 'critical').Count
      high     = @($all | Where-Object severity -eq 'high').Count
      medium   = @($all | Where-Object severity -eq 'medium').Count
      low      = @($all | Where-Object severity -eq 'low').Count
      total    = @($all).Count
    }
    findings = $all
  }
  $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

  Write-ReportMarkdown -Findings $all -Changed $changed -OutPath $mdPath -Payload $payload

  # ---------- Comparison view (Prompt 2) ----------
  if ($ComparePasses) {
    Write-Step "Per-file vs cross-file comparison"
    Write-Host ("Per-file pass : {0} local issue(s) across {1} file(s) - each found looking at ONE file." -f @($perFile).Count, @($perFile | Select-Object -ExpandProperty file -Unique).Count)
    Write-Host ("Cross-file pass: {0} contract issue(s) the per-file pass structurally COULD NOT see:" -f @($crossFile).Count) -ForegroundColor Yellow
    foreach ($f in $crossFile) { Write-Host ("   - {0}:{1} [{2}] {3}" -f $f.file, $f.line, $f.severity, $f.issue) -ForegroundColor DarkYellow }
  }

  # ---------- Console summary + exit code ----------
  Write-Step "Summary"
  $c = $payload.counts
  Write-Host ("critical {0} | high {1} | medium {2} | low {3} | total {4}" -f $c.critical,$c.high,$c.medium,$c.low,$c.total)
  Write-Info ("Wrote {0} and {1}" -f (Resolve-Path $jsonPath), (Resolve-Path $mdPath))

  if ($FailOn -eq 'none') { exit 0 }
  $threshold = $Rank[$FailOn]
  $blocking = @($all | Where-Object { $Rank[$_.severity] -ge $threshold })
  if ($blocking.Count -gt 0) {
    Write-Host ("`nFAIL: {0} finding(s) at or above '{1}'. Blocking merge." -f $blocking.Count, $FailOn) -ForegroundColor Red
    exit 1
  }
  Write-Host ("`nPASS: no findings at or above '{0}'." -f $FailOn) -ForegroundColor Green
  exit 0
}
finally {
  Pop-Location
}
