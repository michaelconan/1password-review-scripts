# 1password-review-scripts

Administrative management scripts to configure, review, and update items stored in 1Password for security and organisation.

## Setup

The scripts require:
- A [1Password subscription](https://1password.com/).
- The [1Password CLI](https://developer.1password.com/docs/cli) (op) installed and configured.
- [PowerShell](https://github.com/PowerShell/PowerShell) (Core) 7.0 or newer is recommended for the best experience, although PowerShell 5.1 is supported.

On Windows, these scripts are designed to run in PowerShell.

## Management Scripts

The following scripts have been developed to be run locally for management tasks.

  Script                  |  Purpose
--------------------------|------------------------------------------------
`Get-Untagged-Items.ps1`  | Identify items without tags to categorise
`Add-Rotation-Fields.ps1` | Add metadata fields for password rotation scripts or SSO tags
`Get-Stale-Items.ps1`     | Identify items due for password rotation by category
`New-Item-Password.ps1`   | Generate new password for 1Password item and update metadata
