{{/* Copyright (c) 2026, Oracle and/or its affiliates.
Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl. */}}
{{/* Validate required configuration before producing any MicroTx resources. */}}
{{- define "obaas.otmm.validateStorage" -}}
{{- $storage := .Values.otmm.coordinator.storage -}}
{{- if .Values.otmm.coordinator.enabled -}}
{{- if not (has $storage.type (list "memory" "db" "etcd")) -}}
{{- fail "otmm.coordinator.storage.type must be memory, db, or etcd" -}}
{{- end -}}
{{- if and (eq $storage.type "memory") (ne (int .Values.otmm.coordinator.replicas) 1) -}}
{{- fail "memory coordinator storage requires replicas: 1; use db or etcd for multiple replicas" -}}
{{- end -}}
{{- if eq $storage.type "db" -}}
{{- if $storage.db.credentialSecretName -}}
{{- $_ := required "A separate coordinator credential secret requires otmm.coordinator.storage.db.connectionString" $storage.db.connectionString -}}
{{- end -}}
{{- if and $storage.db.walletConfigMapName $storage.db.walletSecretName -}}
{{- fail "Configure only one of walletConfigMapName and walletSecretName" -}}
{{- end -}}
{{- else if eq $storage.type "etcd" -}}
{{- $_ := required "etcd storage requires otmm.coordinator.storage.etcd.endpoints" $storage.etcd.endpoints -}}
{{- if ne (empty $storage.etcd.credentialSecretName) (empty $storage.etcd.caConfigMapName) -}}
{{- fail "etcd TLS requires both credentialSecretName and caConfigMapName" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $fs := .Values.otmm.workflowServer.config.storage.fileSystem.persistence -}}
{{- if and .Values.otmm.workflowServer.enabled $fs.enabled (not (has "ReadWriteMany" $fs.accessModes)) (gt (int .Values.otmm.workflowServer.replicas) 1) -}}
{{- fail "Multiple workflow replicas require shared ReadWriteMany file storage" -}}
{{- end -}}
{{- if and .Values.otmm.workflowServer.enabled $fs.enabled $fs.retain .Values.global.cleanupPVCs -}}
{{- fail "Retaining workflow files requires global.cleanupPVCs: false; the namespace cleanup hook otherwise deletes retained PVCs" -}}
{{- end -}}
{{- end -}}

{{- define "obaas.otmm.workflowClaim" -}}
{{- .Values.otmm.workflowServer.config.storage.fileSystem.persistence.existingClaim | default (printf "%s-otmm-workflow-files" .Release.Name | trunc 63 | trimSuffix "-") -}}
{{- end -}}

{{/* Shared startup configuration for schema initialization and the coordinator. */}}
{{- define "obaas.otmm.coordinatorConfig" -}}
{{- $root := .root -}}
{{- $storage := $root.Values.otmm.coordinator.storage -}}
{{- $sharedDatabase := and (eq $storage.type "db") (not $storage.db.credentialSecretName) -}}
{{- $databaseWallet := or $storage.db.walletConfigMapName $storage.db.walletSecretName $sharedDatabase -}}
{{- $mountStorage := or (and (eq $storage.type "db") $databaseWallet) (and (eq $storage.type "etcd") $storage.etcd.credentialSecretName) -}}
{{- if $sharedDatabase }}
# MicroTx expects JSON credentials; serialize the shared secret at runtime.
command: ["/usr/bin/python3", "-c"]
args:
- |
  import json, os
  os.environ["STORAGE_DB_CREDENTIAL"] = json.dumps({
      "username": os.environ.pop("DB_USERNAME"),
      "password": os.environ.pop("DB_PASSWORD"),
  })
  os.environ["STORAGE_DB_CONNECTION_STRING"] = {{ $storage.db.connectionString | toJson }} or os.environ["DB_DSN"]
  os.execv("/app/tcs", ["/app/tcs"])
{{- end }}
# Use one configuration source so secret-backed environment settings apply.
envFrom:
- configMapRef:
    name: {{ $root.Release.Name }}-otmm-config
env:
- name: INIT_CONTAINER_ENABLED
  value: {{ .initialize | quote }}
- name: GIN_MODE
  value: release
{{- if eq $storage.type "db" }}
{{- if $sharedDatabase }}
{{- include "obaas.database.authN" $root | nindent 0 }}
{{- else }}
- name: STORAGE_DB_CREDENTIAL
  valueFrom:
    secretKeyRef:
      name: {{ $storage.db.credentialSecretName | quote }}
      key: {{ $storage.db.credentialSecretKey | quote }}
{{- end }}
{{- if $databaseWallet }}
- name: TNS_ADMIN
  value: /etc/config/dbwallet
{{- end }}
{{- end }}
{{- if $mountStorage }}
volumeMounts:
{{- if and (eq $storage.type "db") $databaseWallet }}
- name: database-wallet
  mountPath: /etc/config/dbwallet
  readOnly: true
{{- else if and (eq $storage.type "etcd") $storage.etcd.credentialSecretName }}
- name: etcd-credentials
  mountPath: /etcdecert
  readOnly: true
- name: etcd-ca
  mountPath: /etcdcacert
  readOnly: true
{{- end }}
{{- end }}
{{- end -}}
