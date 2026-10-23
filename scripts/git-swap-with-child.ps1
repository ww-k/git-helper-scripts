[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$CommitId
)

# swap-with-child.sh <commit-ish>
# 交换 <commit-ish> 与其直接子提交的位置
# 例: A→B→C→D 传入 B  =>  A→C→B→D
# 临时分支基于 TARGET^ 创建; 原分支全程不动

$ErrorActionPreference = 'Stop'
$SafeDirectory = (Get-Location).Path

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -c "safe.directory=$SafeDirectory" -c core.excludesFile= @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw (($output | ForEach-Object { $_.ToString() }) -join "`n")
    }
    return $output
}

function Invoke-GitText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    return ((Invoke-Git $Arguments | ForEach-Object { $_.ToString() }) -join "`n").Trim()
}

function Test-CleanWorktree {
    & git -c "safe.directory=$SafeDirectory" -c core.excludesFile= diff --quiet
    $unstaged = $LASTEXITCODE
    & git -c "safe.directory=$SafeDirectory" -c core.excludesFile= diff --cached --quiet
    $staged = $LASTEXITCODE
    if ($unstaged -ne 0 -or $staged -ne 0) {
        throw 'Error: worktree has uncommitted changes'
    }
}

if (-not $CommitId) {
    throw 'Usage: .\git-swap-with-child.ps1 <commit-id>'
}

$target = Invoke-GitText @('rev-parse', '--verify', "${CommitId}^{commit}")
$child = (& git -c "safe.directory=$SafeDirectory" -c core.excludesFile= rev-list --ancestry-path --reverse "${target}..HEAD" 2>$null | Select-Object -First 1 | Out-String).Trim()
if (-not $child) {
    throw "No child commit found for $target"
}

foreach ($commit in @($target, $child)) {
    $parents = Invoke-GitText @('rev-list', '--parents', '-n', '1', $commit)
    $parentCount = ($parents -split '\s+').Count
    if ($parentCount -ne 2) {
        throw "Unsupported merge commit: $commit"
    }
}

Test-CleanWorktree
Invoke-Git @('merge-base', '--is-ancestor', $target, 'HEAD') | Out-Null

$origBranch = (& git -c "safe.directory=$SafeDirectory" -c core.excludesFile= symbolic-ref --short -q HEAD 2>$null | Out-String).Trim()
if ($LASTEXITCODE -eq 0 -and $origBranch) {
    $origRef = "refs/heads/$origBranch"
} else {
    $origBranch = ''
    $origRef = Invoke-GitText @('rev-parse', 'HEAD')
}

$parentOfTarget = Invoke-GitText @('rev-parse', '--verify', "${target}^")
$later = @(Invoke-Git @('rev-list', '--reverse', "${child}..HEAD") | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
$tmp = "__swap_tmp_$([DateTimeOffset]::Now.ToUnixTimeSeconds())"

try {
    Invoke-Git @('checkout', '-b', $tmp, $parentOfTarget) | Out-Null
    Invoke-Git @('cherry-pick', $child) | Write-Host
    Invoke-Git @('cherry-pick', $target) | Write-Host
    foreach ($commit in $later) {
        Invoke-Git @('cherry-pick', $commit) | Write-Host
    }

    if ($origBranch) {
        Invoke-Git @('checkout', '-q', $origBranch) | Out-Null
        Invoke-Git @('reset', '--hard', $tmp) | Write-Host
        Invoke-Git @('branch', '-D', $tmp) | Write-Host
    } else {
        Invoke-Git @('checkout', '-q', '--detach', $tmp) | Out-Null
        Invoke-Git @('branch', '-D', $tmp) | Write-Host
    }
} catch {
    & git -c "safe.directory=$SafeDirectory" -c core.excludesFile= checkout -q $origRef 2>$null
    & git -c "safe.directory=$SafeDirectory" -c core.excludesFile= branch -D $tmp 2>$null
    throw
}
