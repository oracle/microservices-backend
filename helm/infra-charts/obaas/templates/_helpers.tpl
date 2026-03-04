{{/*
Copyright (c) 2024, 2026, Oracle and/or its affiliates.
Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.
*/}}
{{/*
Expand the name of the chart.
*/}}
{{/*
Image Pull Secrets Helper
Renders imagePullSecrets block with local-first fallback to global.
Usage: {{ include "obaas.imagePullSecrets" (dict "local" .Values.component.imagePullSecrets "global" .Values.global.imagePullSecrets) | nindent 6 }}
*/}}
{{- define "obaas.imagePullSecrets" -}}
{{- $local := .local -}}
{{- $global := .global -}}
{{- if or $local $global }}
imagePullSecrets:
  {{- if $local }}
  {{- toYaml $local | nindent 2 }}
  {{- else }}
  {{- toYaml $global | nindent 2 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Image Pull Secret Name Helper
Returns the name of the first image pull secret (local-first, fallback to global).
Useful for config values that need just the secret name, not the full block.
Usage: {{ include "obaas.imagePullSecretName" (dict "local" .Values.component.imagePullSecrets "global" .Values.global.imagePullSecrets) }}
*/}}
{{- define "obaas.imagePullSecretName" -}}
{{- $local := .local -}}
{{- $global := .global -}}
{{- if $local -}}
{{ (index $local 0).name }}
{{- else if $global -}}
{{ (index $global 0).name }}
{{- else -}}
""
{{- end -}}
{{- end }}

{{/*
Expand the name of the chart.
*/}}
{{- define "obaas.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "obaas.fullname" -}}
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
{{- define "obaas.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "obaas.labels" -}}
obaas.sh/chart: {{ include "obaas.chart" . }}
{{ include "obaas.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "obaas.selectorLabels" -}}
app.kubernetes.io/name: {{ include "obaas.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "obaas.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "obaas.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the signoz authentication secret name
*/}}
{{- define "obaas.signoz.secretName" -}}
{{- if .Values.signoz.auth.existingSecret }}
{{- .Values.signoz.auth.existingSecret }}
{{- else }}
{{- print "signoz-authn" }}
{{- end }}
{{- end }}

{{/*
Compute the SigNoz subchart's fullname, mirroring signoz.fullname logic.
Honors signoz.nameOverride and signoz.fullnameOverride from parent values.
*/}}
{{- define "obaas.signoz.fullname" -}}
{{- if .Values.signoz.fullnameOverride -}}
{{- .Values.signoz.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default "signoz" .Values.signoz.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Generate a random password for database credentials
*/}}
{{- define "obaas.randomPassword" -}}
  {{- $minLen := 16 -}}
  {{- $maxLen := 30 -}}
  {{- $one := int 1 -}}
  {{- $two := int 2 -}}

  {{- /* Random length between min and max */ -}}
  {{- $range := int (add (sub $maxLen $minLen) 1) -}}
  {{- $randOffset := int (randInt 0 $range) -}}
  {{- $length := add $minLen $randOffset -}}

  {{- /* Required characters: 2 upper, 2 lower, 2 digits, 2 special */ -}}
  {{- $upper1 := randAlpha $one | upper -}}
  {{- $upper2 := randAlpha $one | upper -}}
  {{- $lower1 := randAlpha $one | lower -}}
  {{- $lower2 := randAlpha $one | lower -}}
  {{- $digit1 := randNumeric $one -}}
  {{- $digit2 := randNumeric $one -}}
  {{- $start := randAlpha $one | lower -}}

  {{- /* Special characters, from "-" and "_" */ -}}
  {{- $specialChars := list "-" "_" -}}
  {{- $specialIndex1 := int (randInt 0 $two) -}}
  {{- $special1 := index $specialChars $specialIndex1 -}}
  {{- $specialIndex2 := int (randInt 0 $two) -}}
  {{- $special2 := index $specialChars $specialIndex2 -}}

  {{- /* Remaining characters to reach desired length (9 required chars above) */ -}}
  {{- $restLength := int (sub $length 9) -}}
  {{- $rest := randAlphaNum $restLength -}}

  {{- /* Final password: start with lowercase letter, then mix required chars */ -}}
  {{- $password := printf "%s%s%s%s%s%s%s%s%s%s" $start $upper1 $special1 $lower1 $digit1 $rest $upper2 $digit2 $special2 $lower2 -}}
  {{- $password -}}
{{- end }}

{{/*
Database Secret Name
*/}}
{{- define "obaas.databaseSecret" -}}
{{- if and .Values.database .Values.database.authN }}
  {{- $authN := .Values.database.authN | default dict }}
  {{- $secretName := $authN.secretName | default "" }}
  {{- if $secretName -}}
    {{- $secretName -}}
  {{- else -}}
    {{- printf "%s-db-authn" .Release.Name -}}
  {{- end -}}
{{- else -}}
  {{- printf "%s-db-authn" .Release.Name -}}
{{- end -}}
{{- end -}}

{{/*
Environment to include Database Authentication
*/}}
{{- define "obaas.database.authN" -}}
- name: DB_USERNAME
  valueFrom:
    secretKeyRef:
        name: {{ include "obaas.databaseSecret" . }}
        key: {{ if .Values.database.authN }}{{ default "username" .Values.database.authN.usernameKey }}{{ else }}username{{ end }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
        name: {{ include "obaas.databaseSecret" . }}
        key: {{ if .Values.database.authN }}{{ default "password" .Values.database.authN.passwordKey }}{{ else }}password{{ end }}
- name: DB_DSN
  valueFrom:
    secretKeyRef:
        name: {{ include "obaas.databaseSecret" . }}
        key: {{ if .Values.database.authN }}{{ default "service" .Values.database.authN.serviceKey }}{{ else }}service{{ end }}
{{- end }}

{{- define "obaas.database.authN.username" -}}
{{- if .secret -}}
{{ $username := index ( index (.secret) "data" ) .key  }}
{{- if not $username }}
{{ fail (printf "db-authN secret does not contain username (key = %s)" .key) }}
{{- else -}}
{{ $username | b64dec }}
{{- end -}}
{{- else -}}
{{ fail "db-authN secret not provided" }}
{{- end -}}
{{- end }}

{{- define "obaas.database.authN.password" -}}
{{- if .secret -}}
{{ $password := index ( index (.secret) "data" ) .key  }}
{{- if not $password }}
{{ fail (printf "db-authN secret does not contain password (key = %s)" .key) }}
{{- else -}}
{{ $password | b64dec }}
{{- end -}}
{{- else -}}
{{ fail "db-authN secret not provided" }}
{{- end -}}
{{- end }}

{{- define "obaas.database.authN.service" -}}
{{- if .secret -}}
{{ $service := index ( index (.secret) "data" ) .key  }}
{{- if not $service }}
{{ fail (printf "db-authN secret does not contain service (key = %s)" .key) }}
{{- else -}}
{{ $service | b64dec }}
{{- end -}}
{{- else -}}
{{ fail "db-authN secret not provided" }}
{{- end -}}
{{- end }}

{{/*
Database ADB wallet secret name
*/}}
{{- define "obaas.databaseAdbWalletSecret" -}}
{{- printf "%s-adb-wallet-pass-%d" $.Release.Name $.Release.Revision -}}
{{- end -}}

{{- define "obaas.databaseAdbTnsAdminSecret" -}}
{{- printf "%s-adb-tns-admin-%d" $.Release.Name $.Release.Revision -}}
{{- end -}}

{{- define "obaas.ociConfigMapName" -}}
{{- printf "%s-oci-config" $.Release.Name -}}
{{- end -}}

{{- define "obaas.databaseTnsAdminSecret" -}}
{{- printf "%s-database-tns-admin-%d" $.Release.Name $.Release.Revision -}}
{{- end -}}

{{/*
Validate that database.other fields are provided when database type is OTHER.
Requires either 'dsn' OR all of (host, port, service_name).
*/}}
{{- define "obaas.database.validateOtherType" -}}
  {{- if .Values.database -}}
    {{- $dbType := .Values.database.type | default "" -}}

    {{- if eq $dbType "OTHER" -}}
      {{- $dsn := .Values.database.other.dsn -}}
      {{- $host := .Values.database.other.host -}}
      {{- $port := .Values.database.other.port -}}
      {{- $serviceName := .Values.database.other.service_name -}}

      {{- /* Check if dsn is provided and not empty */ -}}
      {{- $hasDsn := false -}}
      {{- if $dsn -}}
        {{- if and (kindIs "string" $dsn) (ne ($dsn | trim) "") -}}
          {{- $hasDsn = true -}}
        {{- end -}}
      {{- end -}}

      {{- /* Check if individual fields are provided */ -}}
      {{- $hasHost := false -}}
      {{- if $host -}}
        {{- if or (not (kindIs "string" $host)) (ne ($host | trim) "") -}}
          {{- $hasHost = true -}}
        {{- end -}}
      {{- end -}}

      {{- $hasPort := false -}}
      {{- if $port -}}
        {{- if or (not (kindIs "string" $port)) (ne ($port | trim) "") -}}
          {{- $hasPort = true -}}
        {{- end -}}
      {{- end -}}

      {{- $hasServiceName := false -}}
      {{- if $serviceName -}}
        {{- if or (not (kindIs "string" $serviceName)) (ne ($serviceName | trim) "") -}}
          {{- $hasServiceName = true -}}
        {{- end -}}
      {{- end -}}

      {{- /* Validate: must have either dsn OR all three individual fields */ -}}
      {{- if not $hasDsn -}}
        {{- if not (and $hasHost $hasPort $hasServiceName) -}}
          {{- fail "database.type is OTHER: must provide either 'dsn' OR all of (host, port, service_name)" -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Database Type Helpers
These helpers provide consistent database type checking across templates.
*/}}
{{- define "obaas.database.type" -}}
{{- if .Values.database -}}
  {{- .Values.database.type -}}
{{- end -}}
{{- end -}}

{{- define "obaas.database.isSIDB" -}}
{{- eq (include "obaas.database.type" .) "SIDB-FREE" -}}
{{- end -}}

{{- define "obaas.database.isADBFree" -}}
{{- eq (include "obaas.database.type" .) "ADB-FREE" -}}
{{- end -}}

{{- define "obaas.database.isADBS" -}}
{{- eq (include "obaas.database.type" .) "ADB-S" -}}
{{- end -}}

{{- define "obaas.database.isOther" -}}
{{- eq (include "obaas.database.type" .) "OTHER" -}}
{{- end -}}

{{- define "obaas.database.isADB" -}}
{{- or (eq (include "obaas.database.type" .) "ADB-S") (eq (include "obaas.database.type" .) "ADB-FREE") -}}
{{- end -}}

{{- define "obaas.database.isContainerDB" -}}
{{- or (eq (include "obaas.database.type" .) "SIDB-FREE") (eq (include "obaas.database.type" .) "ADB-FREE") -}}
{{- end -}}

{{- define "obaas.database.needsPrivAuth" -}}
{{- or (eq (include "obaas.database.isADBS" .) "true") (eq (include "obaas.database.isOther" .) "true") -}}
{{- end -}}

{{/*
Validate that privAuthN.secretName is provided for database types that require it.
ADB-S and OTHER are pre-existing databases where the admin credentials already exist,
so users must provide the secret reference.
*/}}
{{- define "obaas.database.validatePrivAuthN" -}}
  {{- if .Values.database -}}
    {{- if eq (include "obaas.database.needsPrivAuth" .) "true" -}}
      {{- $secretName := "" -}}
      {{- if .Values.database.privAuthN -}}
        {{- if .Values.database.privAuthN.secretName -}}
          {{- if kindIs "string" .Values.database.privAuthN.secretName -}}
            {{- $secretName = .Values.database.privAuthN.secretName | trim -}}
          {{- end -}}
        {{- end -}}
      {{- end -}}
      {{- if eq $secretName "" -}}
        {{- $dbType := include "obaas.database.type" . -}}
        {{- fail (printf "database.type is %s: privAuthN.secretName is REQUIRED. For pre-existing databases, you must provide a secret containing the privileged user (ADMIN for ADB, SYSTEM for non-ADB) credentials." $dbType) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Database Service Name Helper
Returns the short database type prefix (sidb or adb) for service naming.
*/}}
{{- define "obaas.database.dbName" -}}
{{- $dbType := include "obaas.database.type" . -}}
{{- if $dbType -}}
  {{- lower (split "-" $dbType)._0 -}}
{{- end -}}
{{- end -}}

{{/*
Validate that if oci_config.configMapName is specified,
then none of the other OCI config values (tenancy, user, fingerprint, region) should be provided.
*/}}
{{- define "obaas.ociConfig.validate" -}}
  {{- if $.Values.database.oci_config -}}
    {{- $configMapName := "" -}}
    {{- if $.Values.database.oci_config.configMapName -}}
      {{- if kindIs "string" $.Values.database.oci_config.configMapName -}}
        {{- $configMapName = $.Values.database.oci_config.configMapName | trim -}}
      {{- end -}}
    {{- end -}}

    {{- $tenancy := "" -}}
    {{- if $.Values.database.oci_config.tenancy -}}
      {{- if kindIs "string" $.Values.database.oci_config.tenancy -}}
        {{- $tenancy = $.Values.database.oci_config.tenancy | trim -}}
      {{- end -}}
    {{- end -}}

    {{- $user := "" -}}
    {{- if $.Values.database.oci_config.user -}}
      {{- if kindIs "string" $.Values.database.oci_config.user -}}
        {{- $user = $.Values.database.oci_config.user | trim -}}
      {{- end -}}
    {{- end -}}

    {{- $fingerprint := "" -}}
    {{- if $.Values.database.oci_config.fingerprint -}}
      {{- if kindIs "string" $.Values.database.oci_config.fingerprint -}}
        {{- $fingerprint = $.Values.database.oci_config.fingerprint | trim -}}
      {{- end -}}
    {{- end -}}

    {{- $region := "" -}}
    {{- if $.Values.database.oci_config.region -}}
      {{- if kindIs "string" $.Values.database.oci_config.region -}}
        {{- $region = $.Values.database.oci_config.region | trim -}}
      {{- end -}}
    {{- end -}}

    {{- /* If configMapName is provided, ensure no other config values are provided */ -}}
    {{- if ne $configMapName "" -}}
      {{- if or (ne $tenancy "") (ne $user "") (ne $fingerprint "") (ne $region "") -}}
        {{- fail "database.oci_config.configMapName is specified: you cannot also provide tenancy, user, fingerprint, or region. Either provide configMapName to reference an existing ConfigMap, OR provide the config values to create a new ConfigMap." -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Database Privileged Secret Name (for SIDB-FREE/ADB-FREE admin user)
*/}}
{{- define "obaas.databasePrivSecret" -}}
{{- if and .Values.database .Values.database.privAuthN }}
  {{- $authN := .Values.database.privAuthN | default dict }}
  {{- $secretName := $authN.secretName | default "" }}
  {{- if $secretName -}}
    {{- $secretName -}}
  {{- else -}}
    {{- printf "%s-db-priv-authn" .Release.Name -}}
  {{- end -}}
{{- else -}}
  {{- printf "%s-db-priv-authn" .Release.Name -}}
{{- end -}}
{{- end }}

{{/*
Database Service Value
Computes the database service/connection string based on database type.
For container DBs (SIDB-FREE, ADB-FREE): computed from release name
For external DBs (ADB-S, OTHER): retrieved from user-provided privAuthN secret
*/}}
{{- define "obaas.database.serviceValue" -}}
{{- if eq (include "obaas.database.isContainerDB" .) "true" -}}
{{ include "obaas.fullname" . }}-{{ include "obaas.database.dbName" . }}:1521/FREEPDB1
{{- else if eq (include "obaas.database.needsPrivAuth" .) "true" -}}
{{- $privSecretName := .Values.database.privAuthN.secretName -}}
{{- $privSecretNs := .Values.database.privAuthN.secretNamespace | default .Release.Namespace -}}
{{- $privServiceKey := .Values.database.privAuthN.serviceKey | default "service" -}}
{{- $privSecret := lookup "v1" "Secret" $privSecretNs $privSecretName -}}
{{- if not $privSecret -}}
{{- fail (printf "privAuthN secret '%s' not found in namespace '%s'" $privSecretName $privSecretNs) -}}
{{- end -}}
{{- $serviceValue := index $privSecret.data $privServiceKey | default "" -}}
{{- if not $serviceValue -}}
{{- fail (printf "privAuthN secret '%s' does not contain service key '%s'" $privSecretName $privServiceKey) -}}
{{- end -}}
{{ $serviceValue | b64dec }}
{{- end -}}
{{- end -}}
