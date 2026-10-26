$ErrorActionPreference = 'Continue'

$KubeContext = $env:CLOUDBANK_PF_CONTEXT
$Namespace = $env:CLOUDBANK_PF_NAMESPACE
$Service = $env:CLOUDBANK_PF_SERVICE
$PortMapping = $env:CLOUDBANK_PF_MAPPING
$WindowTitle = $env:CLOUDBANK_PF_TITLE
$ExitCode = 1

try {
    if ([string]::IsNullOrWhiteSpace($KubeContext) -or
        [string]::IsNullOrWhiteSpace($Namespace) -or
        [string]::IsNullOrWhiteSpace($Service) -or
        [string]::IsNullOrWhiteSpace($PortMapping)) {
        throw 'Port-forward settings were not passed to this window.'
    }

    try {
        $Host.UI.RawUI.WindowTitle = $WindowTitle
    }
    catch {
        # Keep the port-forward usable in hosts that do not support window titles.
    }

    Write-Host "Context: $KubeContext"
    Write-Host "Namespace: $Namespace"
    Write-Host "Service: $Service"
    Write-Host "Forwarding: $PortMapping"
    Write-Host ''

    if (-not (Get-Command kubectl -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'kubectl is required and must be available on PATH.'
    }

    & kubectl --context $KubeContext --namespace $Namespace port-forward --address 127.0.0.1 "service/$Service" $PortMapping
    $ExitCode = $LASTEXITCODE
}
catch {
    Write-Host "Port-forward failed: $_" -ForegroundColor Red
}

Write-Host ''
Write-Host "Port-forward exited with status $ExitCode."
try {
    Read-Host 'Press Enter to close this window' | Out-Null
}
catch {
}

exit $ExitCode
