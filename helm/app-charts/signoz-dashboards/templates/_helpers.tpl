{{/* Keep valid short filename stems unchanged. Hash changed names to avoid truncation collisions. */}}
{{- define "signoz-dashboards.safeName" -}}
{{- $original := . -}}
{{- $normalized := regexReplaceAll "[^a-z0-9-]+" (lower $original) "-" | trimAll "-" -}}
{{- if and (eq $original $normalized) (le (len $normalized) 63) (ne $normalized "") -}}
{{- $normalized -}}
{{- else -}}
{{- printf "%s-%s" ($normalized | default "dashboard" | trunc 54 | trimSuffix "-") (sha256sum $original | trunc 8) -}}
{{- end -}}
{{- end -}}

{{- define "signoz-dashboards.configMapName" -}}
{{- include "signoz-dashboards.safeName" (base . | trimSuffix ".json") -}}
{{- end -}}

{{- define "signoz-dashboards.jobName" -}}
{{- include "signoz-dashboards.safeName" (printf "%s-signoz-setup" .Release.Name) -}}
{{- end -}}

{{- define "signoz-dashboards.scriptName" -}}
{{- include "signoz-dashboards.safeName" (printf "%s-dashboard-importer" .Release.Name) -}}
{{- end -}}

{{- define "signoz-dashboards.url" -}}
{{- .Values.signoz.url | default (printf "http://%s-signoz:8080" .Values.signoz.releaseName) -}}
{{- end -}}

