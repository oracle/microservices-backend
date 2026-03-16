{{/*
Copyright (c) 2024, 2025, Oracle and/or its affiliates.
Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.
*/}}

{{/*
Expand the name of the application.
For this shared chart, defaults to the release name (e.g., account, customer)
*/}}
{{- define "obaas-app.name" -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "obaas-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "obaas-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "obaas-app.labels" -}}
helm.sh/chart: {{ include "obaas-app.chart" . }}
{{ include "obaas-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "obaas-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "obaas-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "obaas-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "obaas-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* ====================
    OBaaS Platform Helpers
    ==================== */}}

{{/*
OBaaS platform release name (required, lowercased for K8s compatibility)
*/}}
{{- define "obaas.releaseName" -}}
{{- required "obaas.releaseName is required" .Values.obaas.releaseName | lower }}
{{- end }}

{{/*
OBaaS platform Helm release revision (looked up dynamically)
*/}}
{{- define "obaas.releaseRevision" -}}
{{- $releaseName := include "obaas.releaseName" . }}
{{- $prefix := printf "sh.helm.release.v1.%s.v" $releaseName }}
{{- $secretList := (lookup "v1" "Secret" .Release.Namespace "") }}
{{- $maxVersion := dict "value" 0 }}
{{- if $secretList.items }}
  {{- range $secret := $secretList.items }}
    {{- $name := $secret.metadata.name | default "" }}
    {{- if (and $name (hasPrefix $prefix $name)) }}
      {{- $version := $secret.metadata.labels.version | default "" }}
      {{- if not $version }}
        {{- $version = regexFind "[0-9]+$" $name }}
      {{- end }}
      {{- if $version }}
        {{- $ver := atoi $version }}
        {{- if gt $ver (index $maxVersion "value") }}
          {{- $_ := set $maxVersion "value" $ver }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{- if gt (index $maxVersion "value") 0 }}
  {{- printf "%d" (index $maxVersion "value") }}
{{- else }}
  1
{{- end }}
{{- end }}
{{/*
Database auth secret name
If not provided, defaults to: {{ database.name }}-{{ Release.Name }}-db-authn
Pattern: {{ dbname }}-{{ schema }}-db-authn (e.g., mydb-account-db-authn)
*/}}
{{- define "obaas.database.authN.secretName" -}}
{{- $authN := .Values.database.authN | default dict }}
{{- $secretName := $authN.secretName | default "" }}
{{- if $secretName }}
{{- $secretName }}
{{- else if .Values.database.name }}
{{- printf "%s-%s-db-authn" (.Values.database.name | lower) .Release.Name }}
{{- else }}
{{- required "database.authN.secretName is required (or set database.name)" "" }}
{{- end }}
{{- end }}

{{/*
Database auth secret keys
*/}}
{{- define "obaas.database.authN.usernameKey" -}}
{{- $authN := .Values.database.authN | default dict }}
{{- $authN.usernameKey | default "username" }}
{{- end }}

{{- define "obaas.database.authN.passwordKey" -}}
{{- $authN := .Values.database.authN | default dict }}
{{- $authN.passwordKey | default "password" }}
{{- end }}

{{- define "obaas.database.authN.serviceKey" -}}
{{- $authN := .Values.database.authN | default dict }}
{{- $authN.serviceKey | default "service" }}
{{- end }}

{{/*
Database privileged auth secret name: {{ database.name }}-db-priv-authn (for Liquibase)
Derived from database.name when provided
*/}}
{{- define "obaas.database.privAuthN.secretName" -}}
{{- $privAuthN := .Values.database.privAuthN | default dict }}
{{- $secretName := $privAuthN.secretName | default "" }}
{{- if $secretName }}
{{- $secretName }}
{{- else if .Values.database.name }}
{{- printf "%s-db-priv-authn" (.Values.database.name | lower) }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}

{{- define "obaas.database.privAuthN.usernameKey" -}}
{{- $privAuthN := .Values.database.privAuthN | default dict }}
{{- $privAuthN.usernameKey | default "username" }}
{{- end }}

{{- define "obaas.database.privAuthN.passwordKey" -}}
{{- $privAuthN := .Values.database.privAuthN | default dict }}
{{- $privAuthN.passwordKey | default "password" }}
{{- end }}

{{- define "obaas.database.privAuthN.serviceKey" -}}
{{- $privAuthN := .Values.database.privAuthN | default dict }}
{{- $privAuthN.serviceKey | default "service" }}
{{- end }}

{{/*
Database wallet secret name (dynamically looks up obaas platform revision)
*/}}
{{- define "obaas.database.walletSecret" -}}
{{- $db := .Values.database | default dict }}
{{- $walletSecret := $db.walletSecret | default "" }}
{{- if $walletSecret }}
{{- $walletSecret }}
{{- else }}
{{- printf "%s-adb-tns-admin-%s" (include "obaas.releaseName" .) (include "obaas.releaseRevision" .) }}
{{- end }}
{{- end }}

{{/*
Eureka service name
*/}}
{{- define "obaas.eureka.serviceName" -}}
{{- $eureka := .Values.eureka | default dict }}
{{- $serviceName := $eureka.serviceName | default "" }}
{{- if $serviceName }}
{{- $serviceName }}
{{- else }}
{{- printf "%s-eureka" (include "obaas.releaseName" .) }}
{{- end }}
{{- end }}

{{/*
Eureka service port
*/}}
{{- define "obaas.eureka.port" -}}
{{- $eureka := .Values.eureka | default dict }}
{{- $eureka.port | default 8761 }}
{{- end }}

{{/*
Eureka URL for Spring Boot
*/}}
{{- define "obaas.eureka.url" -}}
{{- printf "http://%s.%s.svc.cluster.local:%d/eureka" (include "obaas.eureka.serviceName" .) .Release.Namespace (int (include "obaas.eureka.port" .)) }}
{{- end }}

{{/*
Spring Cloud Config Server endpoint
*/}}
{{- define "obaas.configServer.endpoint" -}}
{{- $configServer := .Values.configServer | default dict }}
{{- $endpoint := $configServer.endpoint | default "" }}
{{- if $endpoint }}
{{- $endpoint }}
{{- else }}
{{- printf "http://%s-config-server.%s.svc.cluster.local:8080" (include "obaas.releaseName" .) .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
OTEL endpoint
*/}}
{{- define "obaas.otel.endpoint" -}}
{{- $otel := .Values.otel | default dict }}
{{- $endpoint := $otel.endpoint | default "" }}
{{- if $endpoint }}
{{- $endpoint }}
{{- else }}
{{- printf "http://%s-signoz-otel-collector.%s.svc.cluster.local:4318" (include "obaas.releaseName" .) .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
OTMM ConfigMap name
*/}}
{{- define "obaas.otmm.configMapName" -}}
{{- $otmm := .Values.otmm | default dict }}
{{- $configMapName := $otmm.configMapName | default "" }}
{{- if $configMapName }}
{{- $configMapName }}
{{- else }}
{{- printf "%s-otmm-config" (include "obaas.releaseName" .) }}
{{- end }}
{{- end }}

{{/*
OTMM URL key in ConfigMap
*/}}
{{- define "obaas.otmm.urlKey" -}}
{{- $otmm := .Values.otmm | default dict }}
{{- $otmm.urlKey | default "EXTERNAL_ADDR" }}
{{- end }}

{{/*
Spring profiles
*/}}
{{- define "obaas.springboot.profilesActive" -}}
{{- $springboot := .Values.springboot | default dict }}
{{- $springboot.profilesActive | default "default" }}
{{- end }}
