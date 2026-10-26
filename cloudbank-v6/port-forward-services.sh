#!/usr/bin/env bash

set -euo pipefail

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf 'Usage: %s <namespace>\n' "${0##*/}"
    printf 'Open five visible service port-forward windows using the current kubectl context.\n'
    printf 'On Windows, run this from Git Bash or use port-forward-services.ps1.\n'
}

if [[ $# -eq 1 && ( "$1" == '--help' || "$1" == '-h' ) ]]; then
    usage
    exit 0
fi

if [[ $# -ne 1 || -z "${1:-}" || "${1:-}" == -* ]]; then
    usage >&2
    exit 1
fi

NAMESPACE="$1"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
    Darwin*)
        OPERATING_SYSTEM='macos'
        ;;
    Linux*)
        OPERATING_SYSTEM='linux'
        ;;
    MINGW*|MSYS*|CYGWIN*)
        OPERATING_SYSTEM='windows'
        ;;
    *)
        fail "Unsupported operating system: $(uname -s)"
        ;;
esac

command -v kubectl >/dev/null 2>&1 || fail 'kubectl is required.'
if ! KUBE_CONTEXT="$(kubectl config current-context 2>/dev/null)"; then
    fail 'kubectl could not read the current context.'
fi
[[ -n "$KUBE_CONTEXT" ]] || fail 'kubectl has no current context.'

if [[ "$OPERATING_SYSTEM" == 'windows' ]]; then
    if command -v pwsh.exe >/dev/null 2>&1; then
        windows_shell="$(command -v pwsh.exe)"
    elif command -v powershell.exe >/dev/null 2>&1; then
        windows_shell="$(command -v powershell.exe)"
    else
        fail 'PowerShell is required. Run port-forward-services.ps1 from PowerShell, or install PowerShell and run this script from Git Bash.'
    fi

    command -v cygpath >/dev/null 2>&1 || fail 'cygpath is required to launch the Windows PowerShell script from this Bash environment.'
    windows_script="$(cygpath -w "$SCRIPT_DIR/port-forward-services.ps1")"
    exec "$windows_shell" -NoProfile -ExecutionPolicy Bypass -File "$windows_script" "$NAMESPACE"
fi

open_forward_window() {
    local service_name="$1"
    local port_mapping="$2"
    local window_title="$3"

    case "$OPERATING_SYSTEM" in
        macos)
            command -v osascript >/dev/null 2>&1 || fail 'osascript is required to open Terminal windows on macOS.'
            osascript - "$KUBE_CONTEXT" "$NAMESPACE" "$service_name" "$port_mapping" "$window_title" "$SCRIPT_DIR/port-forward-service-window.sh" <<'APPLESCRIPT'
on run argv
    set kubeContext to item 1 of argv
    set namespace to item 2 of argv
    set serviceName to item 3 of argv
    set portMapping to item 4 of argv
    set windowTitle to item 5 of argv
    set helperScript to item 6 of argv

    set commandText to "/bin/bash " & quoted form of helperScript & " " & quoted form of kubeContext & " " & quoted form of namespace & " " & quoted form of serviceName & " " & quoted form of portMapping

    tell application "Terminal"
        activate
        do script commandText
        set custom title of selected tab of front window to windowTitle
    end tell
end run
APPLESCRIPT
            ;;
        linux)
            if command -v gnome-terminal >/dev/null 2>&1; then
                gnome-terminal --title="$window_title" -- bash "$SCRIPT_DIR/port-forward-service-window.sh" "$KUBE_CONTEXT" "$NAMESPACE" "$service_name" "$port_mapping"
            elif command -v x-terminal-emulator >/dev/null 2>&1; then
                x-terminal-emulator -T "$window_title" -e bash "$SCRIPT_DIR/port-forward-service-window.sh" "$KUBE_CONTEXT" "$NAMESPACE" "$service_name" "$port_mapping"
            else
                fail 'No supported graphical terminal found. Install gnome-terminal or x-terminal-emulator on Ubuntu.'
            fi
            ;;
    esac
}

open_forward_window 'azn-server' '8080:8080' 'azn-server - 8080'
open_forward_window 'obaas-otmm-console' '5002:5002' 'OTMM console - 5002'
open_forward_window 'obaas-otmm-workflow-server' '9010:9010' 'OTMM workflow server - 9010'
open_forward_window 'obaas-otmm-tcs' '9000:9000' 'OTMM TCS - 9000'
open_forward_window 'gateway-bff-service' '8089:8089' 'Gateway BFF - 8089'

printf 'Opened five visible port-forward windows for context %s in namespace %s on %s.\n' "$KUBE_CONTEXT" "$NAMESPACE" "$OPERATING_SYSTEM"
