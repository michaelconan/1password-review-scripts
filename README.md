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
| `Get-All-Items-Extended.ps1` | Exports a CSV inventory and optionally one masked full-detail JSON file per item. |

### Common Examples

```powershell
.\src\Get-Untagged-Items.ps1 -Vault private
.\src\Add-Rotation-Fields.ps1 -Vault Shared
.\src\Get-Stale-Items.ps1 -Vault Shared -Tag finance
.\src\New-Item-Password.ps1 -Vault private -Item "My Login"
.\src\Get-All-Items-Extended.ps1 -Vault Shared -ExportPath .\items.csv
.\src\Get-All-Items-Extended.ps1 -AllVaults -ExportPath .\all-items.csv -JsonExportPath .\items-json
```

`-AllVaults` enumerates every vault visible to the authenticated account. `-JsonExportPath` writes
one JSON file per item. The files contain the complete detail response, but values of fields whose
type is `CONCEALED` are replaced with `********`; the CLI is never asked to reveal concealed data.
Existing JSON and CSV files are compared with the new content and left untouched when unchanged.
When `-JsonExportPath` is provided, the JSON files also act as a cache: each item's `updated_at`
value from the list response is compared with the cached detail, and unchanged items do not
require an `op item get` call. Without `-JsonExportPath`, details must be fetched to build the CSV.
Generated CSV files and the default `items-json` directory are ignored by Git.

### DuckDB Views

The JSON export can be queried in DuckDB without importing it into a separate database:

```powershell
duckdb review.duckdb -init .\duckdb\items.sql
duckdb review.duckdb -init .\duckdb\fields.sql
```

The first script creates the `items` view over `items-json\*.json`. The second creates
`fields`, one row per nested field with `item_id` referencing `items.id`. Run both scripts
in the same DuckDB session, or use `.read duckdb/items.sql` and `.read duckdb/fields.sql`.

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

Unit tests live in `tests/Utils.Tests.ps1` and use Pester 5 syntax. The tests focus on pure utility behavior in `src/Utils.ps1`, with mocked `op` calls for CLI wrappers. Vault mutation commands remain integration concerns and are not run by the unit suite.

Coverage is collected for `src/Utils.ps1`:

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
