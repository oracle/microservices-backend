{{/*
Expand the name of the chart.
*/}}
{{- define "oracle-database-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "oracle-database-operator.fullname" -}}
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
{{- define "oracle-database-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Namespace for operator resources
Defaults to release namespace, can be overridden via .Values.namespace
*/}}
{{- define "oracle-database-operator.namespace" -}}
{{- default .Release.Namespace .Values.namespace }}
{{- end }}

{{/*
Namespace for cert-manager
Defaults to release namespace, can be overridden via cert-manager.namespace
*/}}
{{- define "oracle-database-operator.certManagerNamespace" -}}
{{- default .Release.Namespace (index .Values "cert-manager" "namespace") }}
{{- end }}

{{/*
cert-manager webhook service name
When subchart: uses release name prefix
When external: uses externalWebhookServiceName
*/}}
{{- define "oracle-database-operator.certManagerWebhookService" -}}
{{- if index .Values "cert-manager" "enabled" -}}
{{- printf "%s-cert-manager-webhook" .Release.Name -}}
{{- else -}}
{{- .Values.certManagerWaitJob.externalWebhookServiceName | default "cert-manager-webhook" -}}
{{- end -}}
{{- end }}

{{/*
cert-manager ValidatingWebhookConfiguration name
When subchart: uses release name prefix
When external: uses default cert-manager-webhook
*/}}
{{- define "oracle-database-operator.certManagerWebhookConfig" -}}
{{- if index .Values "cert-manager" "enabled" -}}
{{- printf "%s-cert-manager-webhook" .Release.Name -}}
{{- else -}}
cert-manager-webhook
{{- end -}}
{{- end }}

{{/*
Validate namespace-scoped configuration.
Fails if scope.mode is "namespace" but watchNamespaces is empty.
*/}}
{{- define "oracle-database-operator.validateScopeConfig" -}}
{{- if and (eq .Values.scope.mode "namespace") (empty .Values.scope.watchNamespaces) -}}
{{- fail "scope.watchNamespaces must not be empty when scope.mode is 'namespace'. Specify at least one namespace to watch." -}}
{{- end -}}
{{- end }}

{{/*
Common labels
*/}}
{{- define "oracle-database-operator.labels" -}}
helm.sh/chart: {{ include "oracle-database-operator.chart" . }}
{{ include "oracle-database-operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "oracle-database-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "oracle-database-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
control-plane: controller-manager
{{- end }}

{{/*
Service account name
*/}}
{{- define "oracle-database-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else }}
{{- "default" }}
{{- end }}
{{- end }}

{{/*
Controller manager image
*/}}
{{- define "oracle-database-operator.image" -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}

{{/*
Webhook service name
*/}}
{{- define "oracle-database-operator.webhookServiceName" -}}
{{- printf "%s-webhook-service" (include "oracle-database-operator.name" .) }}
{{- end }}

{{/*
Metrics service name
*/}}
{{- define "oracle-database-operator.metricsServiceName" -}}
{{- printf "%s-controller-manager-metrics-service" (include "oracle-database-operator.name" .) }}
{{- end }}

{{/*
Certificate name
*/}}
{{- define "oracle-database-operator.certificateName" -}}
{{- printf "%s-serving-cert" (include "oracle-database-operator.name" .) }}
{{- end }}

{{/*
Issuer name
*/}}
{{- define "oracle-database-operator.issuerName" -}}
{{- printf "%s-selfsigned-issuer" (include "oracle-database-operator.name" .) }}
{{- end }}

{{/*
Cert-manager inject annotation value
*/}}
{{- define "oracle-database-operator.certManagerInjectAnnotation" -}}
{{- printf "%s/%s" (include "oracle-database-operator.namespace" .) (include "oracle-database-operator.certificateName" .) }}
{{- end }}

{{/*
Mutating webhook definitions
Each entry: name, path, apiGroup, apiVersion, resources, operations (optional, defaults to CREATE,UPDATE)
*/}}
{{- define "oracle-database-operator.mutatingWebhooks" -}}
- name: mdbcssystemv4.kb.io
  path: /mutate-database-oracle-com-v4-dbcssystem
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: dbcssystems
- name: mlrest.kb.io
  path: /mutate-database-oracle-com-v4-lrest
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: lrests
- name: mlrpdb.kb.io
  path: /mutate-database-oracle-com-v4-lrpdb
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: lrpdbs
- name: moraclerestart.kb.io
  path: /mutate-database-oracle-com-v4-oraclerestart
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: oraclerestarts
- name: mshardingdatabasev4.kb.io
  path: /mutate-database-oracle-com-v4-shardingdatabase
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: shardingdatabases
- name: mdataguardbroker.kb.io
  path: /mutate-database-oracle-com-v1alpha1-dataguardbroker
  apiGroup: database.oracle.com
  apiVersion: v1alpha1
  resources: dataguardbrokers
- name: moraclerestdataservice.kb.io
  path: /mutate-database-oracle-com-v1alpha1-oraclerestdataservice
  apiGroup: database.oracle.com
  apiVersion: v1alpha1
  resources: oraclerestdataservices
- name: msingleinstancedatabase.kb.io
  path: /mutate-database-oracle-com-v1alpha1-singleinstancedatabase
  apiGroup: database.oracle.com
  apiVersion: v1alpha1
  resources: singleinstancedatabases
- name: mdatabaseobserver.kb.io
  path: /mutate-observability-oracle-com-v4-databaseobserver
  apiGroup: observability.oracle.com
  apiVersion: v4
  resources: databaseobservers
{{- end }}

{{/*
Validating webhook definitions
Each entry: name, path, apiGroup, apiVersion, resources, operations (optional, defaults to CREATE,UPDATE)
*/}}
{{- define "oracle-database-operator.validatingWebhooks" -}}
- name: vautonomouscontainerdatabasev4.kb.io
  path: /validate-database-oracle-com-v4-autonomouscontainerdatabase
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: autonomouscontainerdatabases
- name: vautonomousdatabasebackupv4.kb.io
  path: /validate-database-oracle-com-v4-autonomousdatabasebackup
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: autonomousdatabasebackups
- name: vautonomousdatabaserestorev4.kb.io
  path: /validate-database-oracle-com-v4-autonomousdatabaserestore
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: autonomousdatabaserestores
- name: vautonomousdatabasev4.kb.io
  path: /validate-database-oracle-com-v4-autonomousdatabase
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: autonomousdatabases
- name: vdbcssystemv4.kb.io
  path: /validate-database-oracle-com-v4-dbcssystem
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: dbcssystems
  operations: [CREATE, UPDATE, DELETE]
- name: vlrest.kb.io
  path: /validate-database-oracle-com-v4-lrest
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: lrests
- name: vlrpdb.kb.io
  path: /validate-database-oracle-com-v4-lrpdb
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: lrpdbs
- name: voraclerestart.kb.io
  path: /validate-database-oracle-com-v4-oraclerestart
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: oraclerestarts
  operations: [CREATE, UPDATE, DELETE]
- name: vshardingdatabasev4.kb.io
  path: /validate-database-oracle-com-v4-shardingdatabase
  apiGroup: database.oracle.com
  apiVersion: v4
  resources: shardingdatabases
  operations: [CREATE, UPDATE, DELETE]
- name: vautonomouscontainerdatabasev1alpha1.kb.io
  path: /validate-database-oracle-com-v1alpha1-autonomouscontainerdatabase
  apiGroup: database.oracle.com
  apiVersion: v1alpha1
  resources: autonomouscontainerdatabases
- name: vautonomousdatabasebackupv1alpha1.kb.io
  path: /validate-database-oracle-com-v1alpha1-autonomousdatabasebackup
  apiGroup: database.oracle.com
  apiVersion: v1alpha1
  resources: autonomousdatabasebackups
- name: vautonomousdatabaserestorev1alpha1.kb.io
  path: /validate-database-oracle-com-v1alpha1-autonomousdatabaserestore
  apiGroup: database.oracle.com
  apiVersion: v1alpha1
  resources: autonomousdatabaserestores
- name: vautonomousdatabasev1alpha1.kb.io
  path: /validate-database-oracle-com-v1alpha1-autonomousdatabase
  apiGroup: database.oracle.com
  apiVersion: v1alpha1
  resources: autonomousdatabases
- name: vdataguardbroker.kb.io
  path: /validate-database-oracle-com-v1alpha1-dataguardbroker
  apiGroup: database.oracle.com
  apiVersion: v1alpha1
  resources: dataguardbrokers
- name: voraclerestdataservice.kb.io
  path: /validate-database-oracle-com-v1alpha1-oraclerestdataservice
  apiGroup: database.oracle.com
  apiVersion: v1alpha1
  resources: oraclerestdataservices
- name: vsingleinstancedatabase.kb.io
  path: /validate-database-oracle-com-v1alpha1-singleinstancedatabase
  apiGroup: database.oracle.com
  apiVersion: v1alpha1
  resources: singleinstancedatabases
  operations: [CREATE, UPDATE, DELETE]
- name: vdatabaseobserver.kb.io
  path: /validate-observability-oracle-com-v4-databaseobserver
  apiGroup: observability.oracle.com
  apiVersion: v4
  resources: databaseobservers
{{- end }}
