[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$TestRepo = Join-Path $Root 'test-git-repo'
$ParentScript = Join-Path $Root 'scripts/git-swap-with-parent.ps1'
$ChildScript = Join-Path $Root 'scripts/git-swap-with-child.ps1'

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = @(& git -C $TestRepo @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw (($output | ForEach-Object { $_.ToString() }) -join "`n")
    }
    return $output
}

function Restore-Fixture {
    foreach ($branch in @('test-parent', 'test-child')) {
        & git -C $TestRepo switch -q $branch 2>$null
        & git -C $TestRepo reset --hard -q fixture-d 2>$null
    }
    & git -C $TestRepo switch -q main 2>$null
}

function Assert-Order {
    param([Parameter(Mandatory = $true)][string[]]$Expected)

    $actual = @(Invoke-Git @('log', '--format=%s', '--reverse'))
    if (($actual -join "`n") -ne ($Expected -join "`n")) {
        throw "提交顺序不符合预期:`n$($actual -join "`n")"
    }
}

try {
    Restore-Fixture

    Invoke-Git @('switch', '-q', 'test-parent') | Out-Null
    Push-Location $TestRepo
    try { & $ParentScript fixture-b | Out-Null } finally { Pop-Location }
    Assert-Order @('root fixture', 'commit B fixture', 'commit A fixture', 'commit C fixture', 'commit D fixture')
    Write-Host 'parent swap: ok'

    Invoke-Git @('reset', '--hard', '-q', 'fixture-d') | Out-Null
    Invoke-Git @('switch', '-q', 'test-child') | Out-Null
    Push-Location $TestRepo
    try { & $ChildScript fixture-b | Out-Null } finally { Pop-Location }
    Assert-Order @('root fixture', 'commit A fixture', 'commit C fixture', 'commit B fixture', 'commit D fixture')
    Write-Host 'child swap: ok'
}
finally {
    Restore-Fixture
}
