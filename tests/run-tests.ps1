[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$TestRepo = Join-Path $Root 'test-git-repo'
$ParentScript = Join-Path $Root 'scripts/git-swap-with-parent.ps1'
$ChildScript = Join-Path $Root 'scripts/git-swap-with-child.ps1'

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    # Do not let an inaccessible global excludes file turn a successful Git
    # command's warning into a terminating PowerShell error.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -c "safe.directory=$Repository" -c core.excludesFile= -C $Repository @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw (($output | ForEach-Object { $_.ToString() }) -join "`n")
    }
    return $output
}

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    return Invoke-GitCommand -Repository $TestRepo -Arguments $Arguments
}

function Initialize-Fixture {
    if (Test-Path -LiteralPath $TestRepo) {
        try {
            Invoke-Git @('rev-parse', '--git-dir') | Out-Null
            return
        } catch {
            throw "'$TestRepo' exists but is not a Git repository. Remove it and run the tests again."
        }
    }

    New-Item -ItemType Directory -Path $TestRepo -Force | Out-Null
    Invoke-GitCommand -Repository $TestRepo -Arguments @('init', '-q', '-b', 'main') | Out-Null
    Invoke-Git @('config', 'user.name', 'git-helper-tests') | Out-Null
    Invoke-Git @('config', 'user.email', 'git-helper-tests@example.invalid') | Out-Null

    $commits = @(
        @{ Message = 'root fixture'; File = 'root.txt'; Content = 'root' },
        @{ Message = 'commit A fixture'; File = 'a.txt'; Content = 'A' },
        @{ Message = 'commit B fixture'; File = 'b.txt'; Content = 'B' },
        @{ Message = 'commit C fixture'; File = 'c.txt'; Content = 'C' },
        @{ Message = 'commit D fixture'; File = 'd.txt'; Content = 'D' }
    )

    for ($index = 0; $index -lt $commits.Count; $index++) {
        Set-Content -LiteralPath (Join-Path $TestRepo $commits[$index].File) -Value $commits[$index].Content
        Invoke-Git @('add', $commits[$index].File) | Out-Null
        Invoke-Git @('commit', '-q', '-m', $commits[$index].Message) | Out-Null
        if ($index -eq 2) {
            Invoke-Git @('tag', 'fixture-b') | Out-Null
        }
    }

    Invoke-Git @('tag', 'fixture-d') | Out-Null
    Invoke-Git @('branch', 'test-parent') | Out-Null
    Invoke-Git @('branch', 'test-child') | Out-Null
}

function Restore-Fixture {
    if (-not (Test-Path -LiteralPath $TestRepo)) {
        return
    }
    $branches = @(Invoke-Git @('for-each-ref', '--format=%(refname:short)', 'refs/heads') | ForEach-Object { $_.ToString().Trim() })
    foreach ($branch in @('test-parent', 'test-child')) {
        if ($branches -notcontains $branch) {
            continue
        }
        Invoke-Git @('switch', '-q', $branch) | Out-Null
        Invoke-Git @('reset', '--hard', '-q', 'fixture-d') | Out-Null
    }
    if ($branches -contains 'main') {
        Invoke-Git @('switch', '-q', 'main') | Out-Null
    }
}

function Assert-Order {
    param([Parameter(Mandatory = $true)][string[]]$Expected)

    $actual = @(Invoke-Git @('log', '--format=%s', '--reverse'))
    if (($actual -join "`n") -ne ($Expected -join "`n")) {
        throw "提交顺序不符合预期:`n$($actual -join "`n")"
    }
}

try {
    Initialize-Fixture
    Restore-Fixture

    Invoke-Git @('switch', '-q', 'test-parent') | Out-Null
    Push-Location $TestRepo
    try { & $ParentScript fixture-b *> $null } finally { Pop-Location }
    Assert-Order @('root fixture', 'commit B fixture', 'commit A fixture', 'commit C fixture', 'commit D fixture')
    Write-Host 'parent swap: ok'

    Invoke-Git @('reset', '--hard', '-q', 'fixture-d') | Out-Null
    Invoke-Git @('switch', '-q', 'test-child') | Out-Null
    Push-Location $TestRepo
    try { & $ChildScript fixture-b *> $null } finally { Pop-Location }
    Assert-Order @('root fixture', 'commit A fixture', 'commit C fixture', 'commit B fixture', 'commit D fixture')
    Write-Host 'child swap: ok'
}
finally {
    Restore-Fixture
}
