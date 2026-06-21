param(
    [Parameter(Mandatory=$true)]
    [string]$ApiKey,
    
    [Parameter(Mandatory=$true)]
    [int]$AccountId
)

$Endpoint = "https://api.newrelic.com/graphql"
$Headers = @{
    "API-Key" = $ApiKey
    "Content-Type" = "application/json"
}

Write-Host "Creating New Relic Entities for Account: $AccountId..." -ForegroundColor Cyan

# ---------------------------------------------------------
# 1. Create Alert Policy
# ---------------------------------------------------------
$policyMutation = @"
mutation {
  alertsPolicyCreate(accountId: $AccountId, policy: {
    incidentPreference: PER_POLICY,
    name: "Spring PetClinic Comprehensive Alerts"
  }) {
    id
    name
  }
}
"@

$policyBody = @{ query = $policyMutation } | ConvertTo-Json -Depth 10

Write-Host "Creating Alert Policy..."
$policyResponse = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $Headers -Body $policyBody
$policyId = $policyResponse.data.alertsPolicyCreate.id

if (-not $policyId) {
    Write-Error "Failed to create Alert Policy. Response: $($policyResponse | ConvertTo-Json -Depth 10)"
    exit
}
Write-Host "Success! Created Policy ID: $policyId" -ForegroundColor Green

# ---------------------------------------------------------
# 2. Create NRQL Alert Conditions
# ---------------------------------------------------------
$conditions = @(
    @{
        name = "High Error Rate (>5% for 5 mins)"
        query = "SELECT percentage(count(*), WHERE error IS TRUE) FROM Transaction WHERE appName = 'Spring PetClinic'"
        threshold = 5
        operator = "ABOVE"
    },
    @{
        name = "High JVM Heap (>85% for 5 mins)"
        query = "SELECT average(newrelic.timeslice.value) * 100 FROM Metric WHERE metricTimesliceName = 'Memory/Heap/Utilization' AND appName = 'Spring PetClinic'"
        threshold = 85
        operator = "ABOVE"
    }
)

foreach ($cond in $conditions) {
    $conditionMutation = @"
    mutation {
      alertsNrqlConditionStaticCreate(
        accountId: $AccountId,
        policyId: $policyId,
        condition: {
          name: "$($cond.name)",
          enabled: true,
          nrql: { query: "$($cond.query)" },
          terms: [
            {
              operator: $($cond.operator),
              priority: CRITICAL,
              threshold: $($cond.threshold),
              thresholdDuration: 300,
              thresholdOccurrences: ALL
            }
          ],
          valueFunction: SINGLE_VALUE
        }
      ) {
        id
      }
    }
"@
    $conditionBody = @{ query = $conditionMutation } | ConvertTo-Json -Depth 10
    Write-Host "Creating Alert Condition: $($cond.name)..."
    $conditionResponse = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $Headers -Body $conditionBody
    if ($conditionResponse.data.alertsNrqlConditionStaticCreate.id) {
        Write-Host "  Success! Condition created." -ForegroundColor Green
    } else {
        Write-Warning "  Failed to create condition. $($conditionResponse | ConvertTo-Json -Depth 10)"
    }
}

# ---------------------------------------------------------
# 3. Create Synthetic Monitor (Ping)
# ---------------------------------------------------------
# Note: Since the app runs on localhost, the public pinger will fail.
# We create it as DISABLED by default so it doesn't trigger false alerts immediately.
$syntheticsMutation = @"
mutation {
  syntheticsCreateSimpleMonitor(
    accountId: $AccountId,
    monitor: {
      name: "Spring PetClinic Ping (Disabled)",
      status: DISABLED,
      uri: "http://localhost:8080/",
      locations: { public: ["AWS_US_EAST_1"] },
      period: EVERY_5_MINUTES
    }
  ) {
    errors { description }
  }
}
"@

$syntheticsBody = @{ query = $syntheticsMutation } | ConvertTo-Json -Depth 10

Write-Host "Creating Synthetic Ping Monitor..."
$syntheticsResponse = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $Headers -Body $syntheticsBody
$syncErrors = $syntheticsResponse.data.syntheticsCreateSimpleMonitor.errors
if ($syncErrors) {
    Write-Warning "  Failed to create Synthetic Monitor. Errors: $($syncErrors | ConvertTo-Json)"
} else {
    Write-Host "  Success! Created Synthetic Ping Monitor (Disabled status)." -ForegroundColor Green
}

# ---------------------------------------------------------
# 4. Create Multi-Page Dashboard
# ---------------------------------------------------------
$dashboardMutation = @"
mutation {
  dashboardCreate(
    accountId: $AccountId,
    dashboard: {
      name: "Spring PetClinic Full Observability",
      permissions: PUBLIC_READ_WRITE,
      pages: [
        {
          name: "App Overview",
          widgets: [
            {
              title: "Transaction Duration",
              configuration: { line: { nrqlQueries: [{ accountId: $AccountId, query: "SELECT average(duration) FROM Transaction WHERE appName = 'Spring PetClinic' TIMESERIES" }] } },
              layout: { column: 1, row: 1, height: 3, width: 4 }
            },
            {
              title: "Error Rate",
              configuration: { billboard: { nrqlQueries: [{ accountId: $AccountId, query: "SELECT percentage(count(*), WHERE error IS TRUE) FROM Transaction WHERE appName = 'Spring PetClinic'" }] } },
              layout: { column: 5, row: 1, height: 3, width: 4 }
            },
            {
              title: "Throughput",
              configuration: { line: { nrqlQueries: [{ accountId: $AccountId, query: "SELECT rate(count(*), 1 minute) FROM Transaction WHERE appName = 'Spring PetClinic' TIMESERIES" }] } },
              layout: { column: 9, row: 1, height: 3, width: 4 }
            }
          ]
        },
        {
          name: "JVM Health",
          widgets: [
            {
              title: "Heap Memory Usage",
              configuration: { line: { nrqlQueries: [{ accountId: $AccountId, query: "SELECT average(newrelic.timeslice.value) FROM Metric WHERE metricTimesliceName = 'Memory/Heap/Used' AND appName = 'Spring PetClinic' TIMESERIES" }] } },
              layout: { column: 1, row: 1, height: 3, width: 6 }
            },
            {
              title: "Thread Count",
              configuration: { line: { nrqlQueries: [{ accountId: $AccountId, query: "SELECT average(newrelic.timeslice.value) FROM Metric WHERE metricTimesliceName = 'Threads/all' AND appName = 'Spring PetClinic' TIMESERIES" }] } },
              layout: { column: 7, row: 1, height: 3, width: 6 }
            }
          ]
        },
        {
          name: "Logs Analysis",
          widgets: [
            {
              title: "Log Volume by Severity",
              configuration: { bar: { nrqlQueries: [{ accountId: $AccountId, query: "SELECT count(*) FROM Log WHERE entity.name = 'Spring PetClinic' FACET level TIMESERIES" }] } },
              layout: { column: 1, row: 1, height: 3, width: 6 }
            },
            {
              title: "Recent Error Logs",
              configuration: { table: { nrqlQueries: [{ accountId: $AccountId, query: "SELECT timestamp, message, class, method FROM Log WHERE entity.name = 'Spring PetClinic' AND level = 'ERROR' LIMIT 10" }] } },
              layout: { column: 7, row: 1, height: 3, width: 6 }
            }
          ]
        }
      ]
    }
  ) {
    entityResult { guid }
    errors { description }
  }
}
"@

$dashboardBody = @{ query = $dashboardMutation } | ConvertTo-Json -Depth 10

Write-Host "Creating Multi-Page Dashboard..."
$dashboardResponse = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $Headers -Body $dashboardBody

$dashboardGuid = $dashboardResponse.data.dashboardCreate.entityResult.guid
if (-not $dashboardGuid) {
    Write-Error "Failed to create Dashboard. Response: $($dashboardResponse | ConvertTo-Json -Depth 10)"
} else {
    Write-Host "Success! Created Dashboard GUID: $dashboardGuid" -ForegroundColor Green
}

Write-Host "`nAll done! You can now check your New Relic UI for the new Dashboard, Alerts, and Synthetics." -ForegroundColor Cyan
