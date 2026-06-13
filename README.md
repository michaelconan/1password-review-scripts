# 1password-review-scripts

PowerShell scripts for auditing and maintaining 1Password vault items. The scripts run locally against the 1Password CLI (`op`) and help identify untagged items, set password rotation metadata, find stale passwords, generate replacements, and export review data.

## Requirements

- 1Password CLI (`op`) installed and available on `PATH`.
- An authenticated 1Password CLI session. Run `op signin` before using the scripts.
- Windows PowerShell 5.1 for script execution. PowerShell 7+ is also used by CI and works for development tooling.
- Pester 5+ for the unit test suite.

## Scripts

| Script | Purpose |
| --- | --- |
| `Get-Untagged-Items.ps1` | Lists login, password, and API credential items that have no meaningful tags. Tags matching `secure*` are treated as non-significant. |
| `Add-Rotation-Fields.ps1` | Adds missing `last password update` metadata to items with passwords. It also reports SSO items that should receive the `secure/sso` tag. |
| `Get-Stale-Items.ps1` | Lists items whose `last password update` date is older than the configured cadence for a tag. |
| `New-Item-Password.ps1` | Generates a new password for one item and updates its rotation date. |
| `Get-All-Items-Extended.ps1` | Exports a CSV inventory with security metadata, recipe, last password update, and age. |

### Common Examples

```powershell
.\Get-Untagged-Items.ps1 -Vault private
.\Add-Rotation-Fields.ps1 -Vault Shared
.\Get-Stale-Items.ps1 -Vault Shared -Tag finance
.\New-Item-Password.ps1 -Vault private -Item "My Login"
.\Get-All-Items-Extended.ps1 -Vault Shared -ExportPath .\items.csv
```

Generated CSV files are ignored by Git.

## Tags and Fields

The scripts use tags to decide what should be audited or skipped:

| Tag or pattern | Meaning |
| --- | --- |
| `other/*` | Exclude the item from rotation checks and setup. |
| `secure/sso` | The item signs in through SSO and does not need password rotation. |
| `secure*` | Treated as non-significant by the untagged-item audit. |
| `finance`, `main` | Use a 90-day password rotation cadence. Other tags default to 360 days. |

Custom fields are matched by label:

| Field label | Used for |
| --- | --- |
| `last password update` | Unix timestamp date used by stale-item checks and exports. |
| `password recipe` | Optional password generation recipe for `New-Item-Password.ps1`. |
| `sign in with` | SSO detection for setup and extended export metadata. |

## Password Recipes

`New-Item-Password.ps1` reads the item-level `password recipe` field. If it is missing, the default is:

```text
words,digits,symbols,32
```

Recipes without `words` are passed directly to `op item edit --generate-password`. Recipes containing `words` use local memorable-password generation because the 1Password CLI does not generate word-based passwords. The word list is downloaded from EFF on first use and cached under `%LOCALAPPDATA%\1password-scripts\eff-wordlist.txt`.

## Development

Install the development modules in the PowerShell environment you use for testing:

```powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
```

Run checks with the helper scripts:

```powershell
.\scripts\Lint.ps1
.\scripts\Test.ps1
.\scripts\Test.ps1 -IncludeCoverage
```

The Makefile wraps the same commands when `make` is available:

```powershell
make lint
make test
make coverage
make ci
```

## Testing and Coverage

Unit tests live in `tests/Utils.Tests.ps1` and use Pester 5 syntax. The tests focus on pure utility behavior in `Utils.ps1`, with mocked `op` calls for CLI wrappers. Vault mutation commands remain integration concerns and are not run by the unit suite.

Coverage is collected for `Utils.ps1`:

```powershell
.\scripts\Test.ps1 -IncludeCoverage
```

This writes:

| File | Description |
| --- | --- |
| `coverage/test-results.xml` | JUnit-style test results. |
| `coverage/coverage.xml` | JaCoCo coverage report uploaded by CI. |
| `coverage/summary.txt` | Human-readable coverage summary. |
| `coverage/missed-commands.txt` | Remaining uncovered commands, when any exist. |

The local coverage target is 80%. CI uploads `coverage/coverage.xml` to Codecov, and `codecov.yml` configures PR comments plus 80% project and patch targets.

## CI

GitHub Actions runs two jobs on pushes to `main` and on pull requests:

- `Lint` installs PSScriptAnalyzer and runs `scripts/Lint.ps1`.
- `Test and coverage` installs Pester, runs `scripts/Test.ps1 -IncludeCoverage`, publishes the coverage summary, uploads Codecov data, and stores the coverage artifacts.
