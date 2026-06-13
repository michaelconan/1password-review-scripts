# Agent Context — 1password-review-scripts

## Project overview

PowerShell scripts for administrative management of a 1Password vault. They run locally against the 1Password CLI (`op`) to audit item tags, set up password rotation metadata, identify stale passwords, and generate new ones. All scripts target **Windows PowerShell 5.1** and require an authenticated `op` session.

## Prerequisites

- [1Password CLI](https://developer.1password.com/docs/cli) installed and on `PATH`
- An active `op` session (`op signin`)
- Windows PowerShell 5.1 for script compatibility
- PowerShell 7+ is supported for development tooling and used by CI
- Pester 5+ for unit tests and coverage

## Repository layout

```
Utils.ps1                      # Shared functions — dot-sourced by every script
Get-Untagged-Items.ps1         # Audit: items with no meaningful tags
Add-Rotation-Fields.ps1        # Setup: add rotation metadata to logins
Get-Stale-Items.ps1            # Audit: logins overdue for a password change
New-Item-Password.ps1          # Action: generate a new password for one item
Get-All-Items-Extended.ps1     # Export: full vault export with security metadata
scripts/
  Lint.ps1                     # PSScriptAnalyzer wrapper
  Test.ps1                     # Pester 5 test and coverage wrapper
tests/
  Utils.Tests.ps1              # Pester 5 unit tests for Utils.ps1
codecov.yml                    # Codecov PR comments and coverage targets
```

## Scripts

### `Get-All-Items-Extended.ps1`
Exports a full vault inventory to CSV, enriched with computed security metadata. For each item it records whether SSO or MFA applies, the last password update date (falling back to `created_at` when the rotation field is absent), and the password recipe. Items tagged `other/*` are excluded.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Vault` | `private` | Vault to export |
| `-ExportPath` | `items.csv` | Output CSV path (relative to current directory or absolute) |

Output columns: `Title`, `Username`, `Category`, `Id`, `Vault`, `Security` (comma-separated flags: `SSO`, `MFA`), `Recipe`, `LastPwUpdate`, `DaysSince`.

The output file is gitignored (`*.csv`).

```powershell
.\Get-All-Items-Extended.ps1
.\Get-All-Items-Extended.ps1 -Vault Shared -ExportPath "C:\reports\vault.csv"
```

### `Get-Untagged-Items.ps1`
Lists login, password, and API credential items that have no tags (or only `secure*` tags, which are treated as non-significant). Intended as an audit pass before running the other scripts.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Vault`  | `private` | Vault to inspect |

```powershell
.\Get-Untagged-Items.ps1
.\Get-Untagged-Items.ps1 -Vault Shared
```

### `Add-Rotation-Fields.ps1`
Iterates every login in the vault and adds missing rotation metadata. Two cases are handled (mutually exclusive per item, evaluated in order):

1. Item has a password but no `last password update` field → adds the field, seeded with the item's `created_at` date.
2. Item has a `sign in with` field (SSO) but lacks the `secure/sso` tag → logs a notice (the `op item edit --tags` call is commented out pending CLI support for `ssoLogin` fields).

Items tagged `other/*` are skipped entirely.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Vault`  | `private` | Vault to update |

```powershell
.\Add-Rotation-Fields.ps1
.\Add-Rotation-Fields.ps1 -Vault Shared
```

### `Get-Stale-Items.ps1`
Identifies logins whose `last password update` date exceeds the cadence for their tag. Only items with a password, a `last password update` field, and no `other/*` exclusion tag are evaluated.

Cadences (days):

| Tag | Days |
|-----|------|
| `finance` | 90 |
| `main` | 90 |
| *(any other)* | 360 |

Output is a table sorted by `DaysSinceUpdate` descending.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Vault`  | `private` | Vault to inspect |
| `-Tag`    | *(required)* | Tag to filter logins by |

```powershell
.\Get-Stale-Items.ps1 -Tag finance
.\Get-Stale-Items.ps1 -Vault Shared -Tag main
```

### `New-Item-Password.ps1`
Generates a new password for a single item and updates its `last password update` date to today.

The password recipe is read from a custom `password recipe` field on the item. If that field is absent, the default recipe `words,digits,symbols,32` is used. Recipe format is the same comma-separated string accepted by the `op --generate-password` flag, with one extension: a recipe containing `words` triggers local memorable-password generation (see [Memorable passwords](#memorable-passwords)) since the CLI does not support word-based generation natively.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Vault`  | `private` | Vault containing the item |
| `-Item`   | *(required)* | Item ID or title |

```powershell
.\New-Item-Password.ps1 -Item "MyLogin"
.\New-Item-Password.ps1 -Item "MyLogin" -Vault Shared
```

## Shared utilities (`Utils.ps1`)

Every script dot-sources `Utils.ps1` at the top via `. "$PSScriptRoot\Utils.ps1"`. The file is organised into six sections.

### 1Password CLI wrappers

| Function | Signature | Description |
|----------|-----------|-------------|
| `Get-VaultItems` | `-Vault -Categories[] [-Tag] [-Long]` | Wraps `op item list`; returns parsed JSON array |
| `Get-ItemDetail` | `-Id [-Vault] [-MaxRetries=3] [-RetryDelayMs=1000]` | Wraps `op item get`; retries transient CLI/Desktop App errors and returns parsed JSON for one item |
| `Test-OpTransientError` | `-Message` | Detects retryable `op` errors such as timeouts, Desktop App connection issues, or temporary unavailability |
| `Get-ItemDetails` | `-Items [-ThrottleLimit=10] [-MaxRetries=3] [-RetryDelayMs=1000]` | Fetches full details for a list of items **in parallel** using a runspace pool; returns `@{Login, Details}` pairs |

`Get-ItemDetails` is the performance-critical path. It creates a `RunspacePool` with up to `ThrottleLimit` concurrent threads, fans out all `op item get` calls simultaneously, polls for completion with a `Write-Progress` bar, then collects results. Transient failures are retried sequentially through `Get-ItemDetail`; non-transient failures are warned and skipped. Write operations (`op item edit`) are always kept sequential to avoid concurrent vault mutations.

### Item field helpers

| Function | Signature | Description |
|----------|-----------|-------------|
| `Get-ItemField` | `-Details -Id` or `-Details -Label` | Returns the first matching field object, or `$null`. Pass `-Id` to match on the internal field id, `-Label` to match on the display label |

### Tag helpers

| Function | Signature | Description |
|----------|-----------|-------------|
| `Test-ItemExcluded` | `-Details -Pattern` | Returns `$true` if the item's tags include any value matching the glob `Pattern` |
| `Test-ItemUntagged` | `-Item -ExcludePattern` | Returns `$true` if the item has no tags, or only tags matching `ExcludePattern` |

### Date helpers

| Function | Signature | Description |
|----------|-----------|-------------|
| `ConvertFrom-UnixDate` | `-Timestamp` | Converts a Unix epoch seconds value to a `DateTime` |

The `last password update` field in 1Password stores its value as a Unix timestamp integer; this function is the canonical way to read it.

### Business logic

| Function | Signature | Description |
|----------|-----------|-------------|
| `Get-StaleItemInfo` | `-Login -Details -Days -ExcludePattern` | Returns a `PSCustomObject {Title, ID, LastUpdate, DaysSinceUpdate}` if the item is stale, or `$null` if it should be skipped |
| `Test-NeedsRotationField` | `-Details` | Returns `$true` if the item has a non-null password but no `last password update` field |
| `Get-PasswordRecipe` | `-Details -Default` | Returns the value of the `password recipe` field, or `Default` if the field is absent |
| `Test-ItemSso` | `-Details -SsoTag` | Returns `$true` if the item has a `sign in with` field or the given SSO tag |
| `Test-ItemMfa` | `-Details -MfaTag` | Returns `$true` if the item carries the given MFA tag |
| `Get-ItemExtendedInfo` | `-Details -ExcludePattern -SsoTag -MfaTag` | Returns a `PSCustomObject {Title, Username, Category, Tags, Id, Vault, Security, Recipe, LastPwUpdate, DaysSince}` for one item, or `$null` for excluded items. Falls back to `created_at` when no rotation field exists |

### Password generation

| Function | Signature | Description |
|----------|-----------|-------------|
| `Get-WordList` | `[-CachePath]` | Downloads the EFF large wordlist on first call and caches it; returns a string array of words filtered to 3–8 characters |
| `New-MemorablePassword` | `-RecipeParts[] -Length` | Generates a memorable password from whole words and optional digit/symbol separators |

#### Memorable passwords

`New-MemorablePassword` is invoked when a recipe contains `words`. It:

1. Loads the word list via `Get-WordList`.
2. Builds a character pool for separators from any `digits` and/or `symbols` components in the recipe.
3. Loops until `$Length` characters are built: picks a random word that fits the remaining space (never truncates), randomly uppercases it with 50% probability, appends it, then appends one random separator character if the recipe includes digits or symbols.
4. When remaining space is too small for any word, fills with separator characters (or random lowercase letters if there are no separators).

The EFF wordlist is cached at `%LOCALAPPDATA%\1password-scripts\eff-wordlist.txt`. Delete this file to force a re-download.

## Custom 1Password fields

The scripts read and write the following custom fields by label:

| Label | Type | Section | Used by |
|-------|------|---------|---------|
| `last password update` | Date | `rotation` | `Get-Stale-Items`, `Add-Rotation-Fields`, `New-Item-Password` |
| `password recipe` | Text | *(any)* | `New-Item-Password` |
| `sign in with` | Text | *(any)* | `Add-Rotation-Fields` (SSO detection) |

## Tag conventions

| Pattern | Meaning |
|---------|---------|
| `other/*` | Item is excluded from rotation checks and field setup |
| `secure/sso` | Item uses SSO; no password rotation needed |
| `secure*` | Any secure tag; treated as non-significant for untagged detection |
| `finance`, `main` | Rotation cadence tags (90-day cycle) |

## Testing and coverage

Tests use **Pester 5+**. Use modern Pester constructs such as `BeforeAll`, `BeforeEach`, and `Should -Be`; legacy syntax compatibility is no longer required.

Run the suite:

```powershell
.\scripts\Test.ps1
.\scripts\Test.ps1 -IncludeCoverage
```

`scripts\Test.ps1` creates `coverage/` when needed, runs all tests under `tests/`, writes `coverage/test-results.xml`, and, with `-IncludeCoverage`, writes `coverage/coverage.xml`, `coverage/summary.txt`, and `coverage/missed-commands.txt`. The script disables Pester's built-in test-result exporter and writes a small JUnit-style XML file itself because Pester's exporter can call Windows environment probes that fail under restricted runners.

The coverage target is **80%** for `Utils.ps1`; `scripts\Test.ps1 -IncludeCoverage` fails if coverage falls below the target. Current coverage is over 90% with 61 tests. `codecov.yml` also configures Codecov PR comments and 80% project/patch status targets.

Unit tests cover pure utility behavior, CLI wrapper argument construction, retry handling, and the parallel fetcher. CLI calls are mocked where possible; the `Get-ItemDetails` runspace test uses a temporary `op.cmd` shim on `PATH` so worker runspaces can execute the production command shape without requiring a real 1Password session.

Test fixtures are defined as script-level helper functions at the top of `tests\Utils.Tests.ps1`:

- `New-FakeDetails` — builds a fake item details object with optional password, rotation field, recipe field, tags, and SSO field
- `New-FakeLogin` — builds a fake item summary object with an id and title

Run linting with:

```powershell
.\scripts\Lint.ps1
```

Known lint output currently includes warning-level findings only; CI treats the current wrapper exit status as authoritative.

## CI and artifacts

GitHub Actions runs lint and test/coverage jobs on pushes to `main` and pull requests. The coverage job installs Pester 5, runs `scripts\Test.ps1 -IncludeCoverage`, publishes `coverage/summary.txt` to the step summary, uploads `coverage/coverage.xml` to Codecov, and stores the `coverage/` directory as an artifact.

Generated files under `coverage/` and exported `*.csv` files are ignored by Git.

## Known limitations

- **SSO tag automation is disabled** — `op item edit --tags` errors on `ssoLogin` category items; the relevant lines in `Add-Rotation-Fields.ps1` are commented out pending CLI support.
- **No automatic wordlist refresh** — the EFF wordlist cache is never invalidated automatically; delete it manually to update.
- **`op` must be pre-authenticated** — none of the scripts call `op signin`; callers must authenticate before running.
- **Windows only** — the scripts use `$env:LOCALAPPDATA` and have only been tested on Windows PowerShell 5.1.
