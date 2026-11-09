$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$azureYaml = Get-Content -LiteralPath (Join-Path $root 'azure.yaml') -Raw
$mainBicep = Get-Content -LiteralPath (Join-Path $root 'infra\main.bicep') -Raw
$databaseBicep = Get-Content -LiteralPath (Join-Path $root 'infra\database.bicep') -Raw
$applicationBicep = Get-Content -LiteralPath (Join-Path $root 'infra\application.bicep') -Raw
$azureProfile = Get-Content -LiteralPath (
    Join-Path $root 'src\main\resources\application-azure-postgres.properties') -Raw
$localProfile = Get-Content -LiteralPath (
    Join-Path $root 'src\main\resources\application-postgres.properties') -Raw

foreach ($required in @(
    'azure.springboot: ">=0.1.0"',
    'host: springbootapp'
)) {
    if (-not $azureYaml.Contains($required, [StringComparison]::Ordinal)) {
        throw "azure.yaml is missing the Spring Boot extension contract: $required."
    }
}
foreach ($obsolete in @(
    'hooks:',
    'Configure-Database.ps1',
    'Prepare-Database.ps1',
    'Update-DatabaseFirewall.ps1'
)) {
    if ($azureYaml.Contains($obsolete, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The template must delegate database reconciliation to the extension, not $obsolete."
    }
}
foreach ($output in @(
    'APPLICATION_IDENTITY_ID',
    'APPLICATION_IDENTITY_CLIENT_ID',
    'APPLICATION_PRINCIPAL_ID',
    'DATABASE_HOST',
    'DATABASE_SERVER_ID',
    'DATABASE_OUTBOUND_IPS'
)) {
    if ($mainBicep -notmatch "(?m)^output $output string =") {
        throw "The extension requires the Bicep output $output."
    }
}
if ($mainBicep.Contains('bootstrap-local-ip', [StringComparison]::OrdinalIgnoreCase) -or
    $databaseBicep.Contains('bootstrap-local-ip', [StringComparison]::OrdinalIgnoreCase) -or
    $databaseBicep.Contains('255.255.255.255', [StringComparison]::Ordinal)) {
    throw 'The template must not create unrestricted PostgreSQL bootstrap access.'
}
if ($applicationBicep -notmatch
    "SPRING_PROFILES_ACTIVE'\s*,\s*value:\s*'azure-postgres,spring-data-jpa'") {
    throw 'Azure deployment must activate the dedicated managed-identity PostgreSQL profile.'
}
foreach ($passwordSetting in @(
    'SPRING_DATASOURCE_PASSWORD',
    'SPRING_DATABASE_PASSWORD',
    'SPRING_DATABASE_APP_PASSWORD'
)) {
    if ($applicationBicep.Contains($passwordSetting, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Azure deployment contains forbidden password setting $passwordSetting."
    }
}
foreach ($required in @(
    'spring.sql.init.platform=postgres',
    'spring.datasource.url=',
    'spring.datasource.username=',
    'spring.sql.init.mode=always'
)) {
    if (-not $azureProfile.Contains($required, [StringComparison]::Ordinal)) {
        throw "Managed-identity PostgreSQL profile is missing $required."
    }
}
if ($azureProfile -match '(?im)^\s*spring\.datasource\.password\s*=') {
    throw 'Managed-identity PostgreSQL profile must not supply a password.'
}
if ($localProfile -notmatch '(?im)^\s*spring\.datasource\.password\s*=') {
    throw 'Local PostgreSQL profile must retain explicit password-based development support.'
}
foreach ($obsoletePath in @(
    'scripts\Configure-Database.ps1',
    'scripts\database-identity.sql',
    'scripts\Initialize-DatabaseIdentity.ps1',
    'scripts\Prepare-Database.ps1',
    'scripts\Sync-DatabaseFirewall.ps1',
    'scripts\Update-DatabaseFirewall.ps1'
)) {
    if (Test-Path -LiteralPath (Join-Path $root $obsoletePath)) {
        throw "Obsolete template-owned database bootstrap file remains: $obsoletePath."
    }
}

Write-Host 'The extension-owned managed-identity contract and local PostgreSQL profile remain separate.'
