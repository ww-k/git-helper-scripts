# Git Swap Scripts

The scripts in `scripts/` are maintained by the root repository:

- `scripts/git-swap-with-parent.sh`
- `scripts/git-swap-with-child.sh`
- `scripts/git-swap-with-parent.ps1`
- `scripts/git-swap-with-child.ps1`

`test-git-repo/` is an independent Git repository containing the fixture
history used to test these scripts. Enter it before running the test commands:

```sh
cd test-git-repo
```

See [`test-git-repo/README.md`](test-git-repo/README.md) for the fixture
history, test commands, and reset instructions.

On Windows PowerShell, run the `.ps1` versions from `test-git-repo`:

```powershell
..\scripts\git-swap-with-parent.ps1 fixture-b
..\scripts\git-swap-with-child.ps1 fixture-b
```
