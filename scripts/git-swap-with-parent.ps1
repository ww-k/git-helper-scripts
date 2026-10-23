[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$CommitId
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = @(& git @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw (($output | ForEach-Object { $_.ToString() }) -join "`n")
    }
    return $output
}

function Invoke-GitText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    return ((Invoke-Git $Arguments | ForEach-Object { $_.ToString() }) -join "`n").Trim()
}

function Test-CleanWorktree {
    & git diff --quiet
    $unstaged = $LASTEXITCODE
    & git diff --cached --quiet
    $staged = $LASTEXITCODE
    if ($unstaged -ne 0 -or $staged -ne 0) {
        throw '错误: 工作区/暂存区不干净'
    }
}

if (-not $CommitId) {
    throw '用法: .\git-swap-with-parent.ps1 <commit-id>'
}

$target = Invoke-GitText @('rev-parse', '--verify', "${CommitId}^{commit}")
$parent = Invoke-GitText @('rev-parse', '--verify', "${target}^")

foreach ($commit in @($target, $parent)) {
    $parentCount = (Invoke-GitText @('rev-list', '--parents', '-n', '1', $commit) -split '\s+').Count
    if ($parentCount -ne 2) {
        throw "错误: $commit 是合并提交，不支持"
    }
}

Test-CleanWorktree
Invoke-Git @('merge-base', '--is-ancestor', $target, 'HEAD') | Out-Null

$origBranch = (& git symbolic-ref --short -q HEAD 2>$null | Out-String).Trim()
if ($LASTEXITCODE -eq 0 -and $origBranch) {
    $origRef = "refs/heads/$origBranch"
} else {
    $origBranch = ''
    $origRef = Invoke-GitText @('rev-parse', 'HEAD')
}

Write-Host "启动位置: $(if ($origBranch) { $origBranch } else { 'detached HEAD' })"
Write-Host "目标:     $target  $(Invoke-GitText @('log', '-1', '--format=%s', $target))"
Write-Host "父提交:   $parent  $(Invoke-GitText @('log', '-1', '--format=%s', $parent))"

$later = @(Invoke-Git @('rev-list', '--reverse', "${target}..HEAD") | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
$grandparent = (& git rev-parse --verify "${parent}^" 2>$null | Out-String).Trim()
$tmp = "__swap_tmp_$([DateTimeOffset]::Now.ToUnixTimeSeconds())"

try {
    if ($grandparent) {
        Invoke-Git @('checkout', '-b', $tmp, $grandparent) | Out-Null
    } else {
        Write-Host '提示: 父提交是根提交，使用 orphan 临时分支'
        Invoke-Git @('checkout', '--orphan', $tmp) | Out-Null
        & git rm -rf . *> $null
    }

    Write-Host "→ 应用目标 $target ..."
    Invoke-Git @('cherry-pick', $target) | Write-Host
    Write-Host "→ 应用父提交 $parent ..."
    Invoke-Git @('cherry-pick', $parent) | Write-Host
    if ($later.Count -gt 0) {
        Write-Host '→ 重放后续提交 ...'
        foreach ($commit in $later) {
            Invoke-Git @('cherry-pick', $commit) | Write-Host
        }
    }

    if ($origBranch) {
        Invoke-Git @('checkout', '-q', $origBranch) | Out-Null
        Invoke-Git @('reset', '--hard', $tmp) | Write-Host
        Invoke-Git @('branch', '-D', $tmp) | Write-Host
        Write-Host "✅ 已更新分支 $origBranch"
    } else {
        Invoke-Git @('checkout', '-q', '--detach', $tmp) | Out-Null
        Invoke-Git @('branch', '-D', $tmp) | Write-Host
        Write-Host '✅ detached HEAD 已更新'
    }
} catch {
    Write-Host '→ 失败，回滚'
    & git checkout -q $origRef 2>$null
    & git branch -D $tmp 2>$null
    throw
}
