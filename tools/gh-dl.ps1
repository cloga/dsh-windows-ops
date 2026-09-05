# Compatibility entry point. Mirror-first downloads are retired.
# A trusted SHA-256 is mandatory; never infer success from nonempty output.
param(
    [Parameter(Mandatory, Position=0)][string]$Url,
    [Parameter(Mandatory, Position=1)][string]$Out,
    [Parameter(Mandatory, Position=2)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$Sha256
)
$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'github-network.mjs') download --url $Url --output $Out --sha256 $Sha256
exit $LASTEXITCODE
