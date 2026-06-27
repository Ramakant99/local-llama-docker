param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("cpu", "gpu")]
    [string]$Mode = "cpu",

    [Parameter(Mandatory=$false)]
    [ValidateSet("both", "planner", "agent")]
    [string]$Service = "both",

    [Parameter(Mandatory=$false)]
    [int]$PlannerPort = 8080,

    [Parameter(Mandatory=$false)]
    [int]$AgentPort = 8081,

    [Parameter(Mandatory=$false)]
    [switch]$Stop
)

if ($Stop) {
    Write-Host "Stopping all Llama.cpp containers..." -ForegroundColor Yellow
    docker compose --profile cpu --profile gpu down
    exit
}

Write-Host "Cleaning up previous containers..." -ForegroundColor Gray
docker compose --profile cpu --profile gpu down --remove-orphans

# Determine services to start
$ServicesToStart = @()
if ($Service -eq "both" -or $Service -eq "planner") {
    $ServicesToStart += "planner-$Mode"
}
if ($Service -eq "both" -or $Service -eq "agent") {
    $ServicesToStart += "agent-$Mode"
}

Write-Host "Starting $Service setup in $Mode mode..." -ForegroundColor Cyan
if ($Service -eq "both" -or $Service -eq "planner") {
    Write-Host "Planner: http://localhost:$PlannerPort" -ForegroundColor Gray
    $env:PLANNER_PORT = $PlannerPort
}
if ($Service -eq "both" -or $Service -eq "agent") {
    Write-Host "Agent:   http://localhost:$AgentPort" -ForegroundColor Gray
    $env:AGENT_PORT = $AgentPort
}

docker compose --profile $Mode up -d $ServicesToStart

Write-Host "`nServers are starting!" -ForegroundColor Green
Write-Host "To see logs, run: docker compose logs -f"
Write-Host "To stop, run: .\run.ps1 -Stop"
