[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Namespace
)

$ErrorActionPreference = 'Stop'

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw 'This launcher is for Microsoft Windows. Use port-forward-services.sh on macOS or Linux.'
}

$KubectlCommand = Get-Command kubectl -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $KubectlCommand) {
    throw 'kubectl is required and must be available on PATH.'
}

$KubeContext = (& kubectl config current-context 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'kubectl could not read the current context.'
}
if ([string]::IsNullOrWhiteSpace($KubeContext)) {
    throw 'kubectl has no current context.'
}

if ($PSVersionTable.PSEdition -eq 'Core') {
    $PowerShellExecutable = Join-Path $PSHOME 'pwsh.exe'
}
else {
    $PowerShellExecutable = Join-Path $PSHOME 'powershell.exe'
}

$WindowScript = Join-Path $PSScriptRoot 'port-forward-service-window.ps1'
if (-not (Test-Path -LiteralPath $WindowScript -PathType Leaf)) {
    throw "Port-forward window helper was not found: $WindowScript"
}

function ConvertTo-WindowsCommandLineArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    $Builder = New-Object System.Text.StringBuilder
    [void]$Builder.Append([char]34)
    $BackslashCount = 0

    foreach ($Character in $Value.ToCharArray()) {
        if ($Character -eq [char]92) {
            $BackslashCount++
            continue
        }

        if ($Character -eq [char]34) {
            for ($Index = 0; $Index -lt (2 * $BackslashCount + 1); $Index++) {
                [void]$Builder.Append([char]92)
            }
            [void]$Builder.Append([char]34)
            $BackslashCount = 0
            continue
        }

        for ($Index = 0; $Index -lt $BackslashCount; $Index++) {
            [void]$Builder.Append([char]92)
        }
        $BackslashCount = 0
        [void]$Builder.Append($Character)
    }

    for ($Index = 0; $Index -lt (2 * $BackslashCount); $Index++) {
        [void]$Builder.Append([char]92)
    }
    [void]$Builder.Append([char]34)
    return $Builder.ToString()
}

$PortForwards = @(
    @{ Service = 'azn-server'; Mapping = '8080:8080'; Title = 'azn-server - 8080' },
    @{ Service = 'obaas-otmm-console'; Mapping = '5002:5002'; Title = 'OTMM console - 5002' },
    @{ Service = 'obaas-otmm-workflow-server'; Mapping = '9010:9010'; Title = 'OTMM workflow server - 9010' },
    @{ Service = 'obaas-otmm-tcs'; Mapping = '9000:9000'; Title = 'OTMM TCS - 9000' },
    @{ Service = 'gateway-bff-service'; Mapping = '8089:8089'; Title = 'Gateway BFF - 8089' }
)

$EnvironmentNames = @(
    'CLOUDBANK_PF_CONTEXT',
    'CLOUDBANK_PF_NAMESPACE',
    'CLOUDBANK_PF_SERVICE',
    'CLOUDBANK_PF_MAPPING',
    'CLOUDBANK_PF_TITLE'
)
$OriginalEnvironment = @{}
foreach ($Name in $EnvironmentNames) {
    $OriginalEnvironment[$Name] = [System.Environment]::GetEnvironmentVariable($Name, 'Process')
}

$StartedWindows = @()
try {
    foreach ($PortForward in $PortForwards) {
        [System.Environment]::SetEnvironmentVariable('CLOUDBANK_PF_CONTEXT', $KubeContext, 'Process')
        [System.Environment]::SetEnvironmentVariable('CLOUDBANK_PF_NAMESPACE', $Namespace, 'Process')
        [System.Environment]::SetEnvironmentVariable('CLOUDBANK_PF_SERVICE', $PortForward.Service, 'Process')
        [System.Environment]::SetEnvironmentVariable('CLOUDBANK_PF_MAPPING', $PortForward.Mapping, 'Process')
        [System.Environment]::SetEnvironmentVariable('CLOUDBANK_PF_TITLE', $PortForward.Title, 'Process')

        $Arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', $WindowScript)
        $ArgumentLine = ($Arguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument ([string]$_) }) -join ' '
        $WindowProcess = Start-Process `
            -FilePath $PowerShellExecutable `
            -ArgumentList $ArgumentLine `
            -WindowStyle Normal `
            -PassThru

        $StartedWindows += [pscustomobject]@{
            Service = $PortForward.Service
            Mapping = $PortForward.Mapping
            Process = $WindowProcess
        }
    }
}
finally {
    foreach ($Name in $EnvironmentNames) {
        [System.Environment]::SetEnvironmentVariable($Name, $OriginalEnvironment[$Name], 'Process')
    }
}

foreach ($Started in $StartedWindows) {
    Write-Output "Opened $($Started.Service) ($($Started.Mapping)) in window PID $($Started.Process.Id)."
}

Write-Output "Opened five visible port-forward windows for context $KubeContext in namespace $Namespace on Windows."
