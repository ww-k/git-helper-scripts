# Git Swap Script Test Repository

The independent fixture repository is `../test-git-repo/`. Run the commands
below from that repository, or use the test runners from the project root.

This repository is a small linear history for testing:

- `../scripts/git-swap-with-parent.sh`
- `../scripts/git-swap-with-child.sh`
- `../scripts/git-swap-with-parent.ps1` (Windows PowerShell)
- `../scripts/git-swap-with-child.ps1` (Windows PowerShell)

History:

```text
fixture-root -> fixture-a -> fixture-b -> fixture-c -> fixture-d
```

The `test-parent` and `test-child` branches both start at `fixture-d`.

## Test parent swap

```sh
cd ../test-git-repo
git switch test-parent
../scripts/git-swap-with-parent.sh fixture-b
git log --oneline --reverse
```

Windows PowerShell:

```powershell
Set-Location ..\test-git-repo
git switch test-parent
..\scripts\git-swap-with-parent.ps1 fixture-b
git log --oneline --reverse
```

Expected commit order after the swap:

```text
root -> B -> A -> C -> D
```

## Test child swap

```sh
cd ../test-git-repo
git switch test-child
../scripts/git-swap-with-child.sh fixture-b
git log --oneline --reverse
```

Windows PowerShell:

```powershell
Set-Location ..\test-git-repo
git switch test-child
..\scripts\git-swap-with-child.ps1 fixture-b
git log --oneline --reverse
```

Expected commit order after the swap:

```text
root -> A -> C -> B -> D
```

Each test branch can be restored with:

```sh
git reset --hard fixture-d
```

The runners execute both swaps and restore `test-parent` and `test-child` to
`fixture-d` when finished:

```sh
./tests/run-tests.sh
```

```powershell
.\tests\run-tests.ps1
```
