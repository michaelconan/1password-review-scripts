# 1password-review-scripts

Administrative management scripts to configure, review, and update items stored in 1Password for security and organisation.

## Setup

The scripts require a 1password subscription and an installation of the [1password command line interface](https://developer.1password.com/docs/cli). On Windows (currently) bash is not fully supported, so the scripts use PowerShell.

## Management Scripts

The following scripts have been developed to be run locally for management tasks.

  Script                  |  Purpose
--------------------------|------------------------------------------------
`Get-Untagged-Items.ps1`  | Identify items without tags to categorise
`Add-Rotation-Fields.ps1` | Add metadata fields for password rotation scripts or SSO tags
`Get-Stale-Items.ps1`     | Identify items due for password rotation by category
`New-Item-Password.ps1`   | Generate new password for 1Password item and update metadata
