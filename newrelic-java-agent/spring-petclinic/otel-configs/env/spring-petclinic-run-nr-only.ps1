# NR-only startup script for spring-petclinic (PowerShell)
# The app sends telemetry ONLY to New Relic via the NR Java agent.
# OTel Collector / ClickHouse / HyperDX containers may still be running
# in docker-compose, but the app does not attach the OTel agent.

param(
    [string]$LicenseKey = $env:NEW_RELIC_LICENSE_KEY
)

if ([string]::IsNullOrWhiteSpace($LicenseKey)) {
    Write-Error "NEW_RELIC_LICENSE_KEY is not set. Pass it as -LicenseKey or set the environment variable."
    exit 1
}

$env:NEW_RELIC_LICENSE_KEY = $LicenseKey
$env:NEW_RELIC_EXPERIMENTAL_RUNTIME = "false"

$JarFile = Get-ChildItem "target/*.jar" | Select-Object -First 1 -ExpandProperty FullName
if (-not $JarFile) {
    Write-Error "No JAR file found in target/. Run 'mvnw package' first."
    exit 1
}

Write-Host "Starting Spring PetClinic with New Relic agent only..." -ForegroundColor Green
Write-Host "JAR: $JarFile" -ForegroundColor Gray

java -javaagent:newrelic/newrelic.jar -jar "$JarFile"
