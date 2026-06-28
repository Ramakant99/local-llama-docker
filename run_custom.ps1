param (
    [Parameter(Mandatory=$true)]
    [string]$ModelFile,

    [Parameter(Mandatory=$false)]
    [int]$Port = 8082,

    [Parameter(Mandatory=$false)]
    [int]$GpuLayers = 99,

    [Parameter(Mandatory=$false)]
    [int]$CtxSize = 128000,

    [Parameter(Mandatory=$false)]
    [int]$ReasoningBudget = -1,

    [Parameter(Mandatory=$false)]
    [string]$MmProj,

    [Parameter(Mandatory=$false)]
    [int]$ImageMinTokens = 0,

    [Parameter(Mandatory=$false)]
    [int]$ImageMaxTokens = 0,

    [Parameter(Mandatory=$false)]
    [switch]$NoFit,

    [Parameter(Mandatory=$false)]
    [switch]$NoFlashAttn,

    [Parameter(Mandatory=$false)]
    [string]$Pooling,

    [Parameter(Mandatory=$false)]
    [switch]$Stop
)

$ContainerName = "llama-custom-gpu"

# Function to check if container exists
function Get-ContainerExists($name) {
    $container = docker ps -a -q --filter "name=^/${name}$"
    return ($null -ne $container -and $container -ne "")
}

if ($Stop) {
    if (Get-ContainerExists $ContainerName) {
        Write-Host "Stopping and removing custom llama container..." -ForegroundColor Yellow
        docker stop $ContainerName 2>$null
        docker rm $ContainerName 2>$null
        Write-Host "Done." -ForegroundColor Green
    } else {
        Write-Host "Container $ContainerName does not exist. Nothing to stop." -ForegroundColor Gray
    }
    exit
}

# Default values if .env is missing or variables are not set
$EnvEmbeddings = "true"
$EnvMlock = "false"
$EnvNoMmap = "false"
$EnvModelsDir = "./models"
$EnvImageTag = "server-cuda"

# Load .env to get shared settings
if (Test-Path ".env") {
    Get-Content ".env" | Where-Object { $_ -match "=" -and $_ -notmatch "^#" } | ForEach-Object {
        $parts = $_.Split('=', 2)
        $name = $parts[0].Trim()
        $value = $parts[1].Trim()
        if ($name -eq "EMBEDDINGS") { $EnvEmbeddings = $value }
        if ($name -eq "MLOCK") { $EnvMlock = $value }
        if ($name -eq "NO_MMAP") { $EnvNoMmap = $value }
        if ($name -eq "MODELS_DIR") { $EnvModelsDir = $value }
        if ($name -eq "IMAGE_TAG_GPU") { $EnvImageTag = $value }
    }
}

$ModelsPath = (Resolve-Path $EnvModelsDir).Path
$FullModelPath = Join-Path $ModelsPath $ModelFile
$WebUiPath = (Resolve-Path "./webui").Path

if (-not (Test-Path $FullModelPath)) {
    Write-Host "Error: Model file not found at $FullModelPath" -ForegroundColor Red
    Write-Host "Available models in $ModelsPath :"
    Get-ChildItem $ModelsPath -Filter *.gguf | Select-Object -ExpandProperty Name
    exit 1
}

$MmProjArg = @()
if ($MmProj) {
    $FullMmProjPath = Join-Path $ModelsPath $MmProj
    if (-not (Test-Path $FullMmProjPath)) {
        Write-Host "Error: Vision projector file not found at $FullMmProjPath" -ForegroundColor Red
        Write-Host "Available projector files in $ModelsPath :"
        Get-ChildItem $ModelsPath -Filter *mmproj* | Select-Object -ExpandProperty Name
        exit 1
    }
    Write-Host "Vision Support: Enabled (using $MmProj)" -ForegroundColor Yellow
    $MmProjArg = "-e", "LLAMA_ARG_MMPROJ=/models/$MmProj"
}

$ImageTokenArgs = @()
if ($ImageMinTokens -gt 0) {
    $ImageTokenArgs += @("-e", "LLAMA_ARG_IMAGE_MIN_TOKENS=$ImageMinTokens")
}
if ($ImageMaxTokens -gt 0) {
    $ImageTokenArgs += @("-e", "LLAMA_ARG_IMAGE_MAX_TOKENS=$ImageMaxTokens")
}

$PoolingArg = @()
if ($Pooling) {
    $PoolingArg = @("-e", "LLAMA_ARG_POOLING=$Pooling")
}

if (Get-ContainerExists $ContainerName) {
    Write-Host "Cleaning up previous custom container..." -ForegroundColor Gray
    docker stop $ContainerName 2>$null
    docker rm $ContainerName 2>$null
}

$FitMode = if ($NoFit) { "off" } else { "on" }
$FlashAttn = if ($NoFlashAttn) { "off" } else { "on" }

Write-Host "Starting custom model: $ModelFile" -ForegroundColor Cyan
Write-Host "URL: http://localhost:$Port" -ForegroundColor Gray
Write-Host "Advanced Flags: Fit=$FitMode, Ctx=$CtxSize, FlashAttn=$FlashAttn, KVQuant=q4_0" -ForegroundColor Gray

$Image = "ghcr.io/ggml-org/llama.cpp:$EnvImageTag"

docker run -d `
    --name $ContainerName `
    --gpus all `
    -p "${Port}:8080" `
    -v "${ModelsPath}:/models" `
    -v "${WebUiPath}:/webui" `
    -e "LLAMA_ARG_STATIC_PATH=/webui" `
    @MmProjArg `
    @ImageTokenArgs `
    @PoolingArg `
    -e "LLAMA_ARG_MODEL=/models/$ModelFile" `
    -e "LLAMA_ARG_N_GPU_LAYERS=$GpuLayers" `
    -e "LLAMA_ARG_CTX_SIZE=$CtxSize" `
    -e "LLAMA_ARG_FIT=$FitMode" `
    -e "LLAMA_ARG_FIT_CTX=$CtxSize" `
    -e "LLAMA_ARG_FIT_TARGET=256" `
    -e "LLAMA_ARG_NP=1" `
    -e "LLAMA_ARG_FLASH_ATTN=$FlashAttn" `
    -e "LLAMA_ARG_CACHE_TYPE_K=q4_0" `
    -e "LLAMA_ARG_CACHE_TYPE_V=q4_0" `
    -e "LLAMA_ARG_REASONING_BUDGET=$ReasoningBudget" `
    -e "LLAMA_ARG_HOST=0.0.0.0" `
    -e "LLAMA_ARG_PORT=8080" `
    -e "LLAMA_ARG_EMBEDDINGS=$EnvEmbeddings" `
    -e "LLAMA_ARG_MLOCK=$EnvMlock" `
    -e "LLAMA_ARG_NO_MMAP=$EnvNoMmap" `
    -e "LLAMA_ARG_TEMP=0.6" `
    -e "LLAMA_ARG_TOP_P=0.95" `
    -e "LLAMA_ARG_TOP_K=20" `
    -e "LLAMA_ARG_MIN_P=0.0" `
    -e "LLAMA_ARG_PRESENCE_PENALTY=0.0" `
    -e "LLAMA_ARG_REPEAT_PENALTY=1.0" `
    -e "LLAMA_ARG_BATCH=2048" `
    -e "LLAMA_ARG_UBATCH=2048" `
    -e "LLAMA_ARG_CHAT_TEMPLATE_KWARGS={\`"preserve_thinking\`": true}" `
    $Image

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nError: Failed to start the container. Please check if Docker is running and your GPU drivers/NVIDIA Container Toolkit are correctly installed." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`nCustom server is starting with optimized reasoning flags!" -ForegroundColor Green
Write-Host "To see logs, run: docker logs -f $ContainerName"
Write-Host "To stop, run: .\run_custom.ps1 -Stop"
