{{/* Copyright (c) 2026, Oracle and/or its affiliates.
Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl. */}}

{{/* Keep existing OBaaS role overrides working while adopting the 26.1 paths.
Legacy overrides take precedence; remove them when migrating to roleMappings. */}}
{{- define "obaas.otmm.coordinatorRoles" -}}
{{- $idp := .Values.otmm.commonConfiguration.security.identityProvider -}}
{{- mergeOverwrite (deepCopy $idp.roleMappings.coordinator) (pick $idp "adminUserRoles" "adminUserRolesPath") | toYaml -}}
{{- end -}}

{{- define "obaas.otmm.workflowRoles" -}}
{{- $idp := .Values.otmm.commonConfiguration.security.identityProvider -}}
{{- $legacy := dig "security" "identityProvider" "policy" (dict) .Values.otmm.workflowServer -}}
{{- mergeOverwrite (deepCopy $idp.roleMappings.workflow) ($idp.policy | default dict) $legacy | toYaml -}}
{{- end -}}

{{- define "obaas.otmm.requestsWithNoJWT" -}}
{{- .Values.otmm.coordinator.authentication.requestsWithNoJWT | default (ternary "DENY" "ALLOW" .Values.otmm.commonConfiguration.security.enabled) -}}
{{- end -}}

{{- define "obaas.otmm.validateSecurity" -}}
{{- $security := .Values.otmm.commonConfiguration.security -}}
{{- $idp := $security.identityProvider -}}
{{- $jwtRequired := eq (include "obaas.otmm.requestsWithNoJWT" .) "DENY" -}}
{{- if and .Values.otmm.coordinator.enabled $security.enabled (not $jwtRequired) -}}
{{- fail "MicroTx security.enabled requires coordinator.authentication.requestsWithNoJWT: DENY (or empty to derive DENY)" -}}
{{- end -}}
{{- if or $security.enabled (and .Values.otmm.coordinator.enabled $jwtRequired) -}}
{{- $_ := required "MicroTx JWT authentication requires otmm.commonConfiguration.security.identityProvider.issuer" $idp.issuer -}}
{{- $_ := required "MicroTx JWT authentication requires otmm.commonConfiguration.security.identityProvider.jwksUri" $idp.jwksUri -}}
{{- end -}}
{{- if and .Values.otmm.coordinator.enabled $jwtRequired -}}
{{- $_ := required "MicroTx coordinator JWT authentication requires identityProvider.audience" $idp.audience -}}
{{- end -}}
{{- if and (ne $idp.serverType "idcs") $idp.scopes -}}
{{- fail "MicroTx identityProvider.scopes is for serverType: idcs only; leave it empty for other providers" -}}
{{- end -}}
{{- if and $security.enabled (eq (include "otmm.console.enabled" .) "true") -}}
{{- $roles := include "obaas.otmm.coordinatorRoles" . | fromYaml -}}
{{- $_ := required "MicroTx console requires security.clientSecretName (Secret keys: clientId, clientPassword)" $security.clientSecretName -}}
{{- $_ := required "MicroTx console requires identityProvider.identityProviderUrl" $idp.identityProviderUrl -}}
{{- $_ := required "MicroTx console requires identityProvider.audience" $idp.audience -}}
{{- $_ := required "MicroTx console requires identityProvider.roleMappings.coordinator.adminUserRoles" $roles.adminUserRoles -}}
{{- $_ := required "MicroTx console requires identityProvider.roleMappings.coordinator.adminUserRolesPath" $roles.adminUserRolesPath -}}
{{- $_ := required "MicroTx console requires console.cookieEncryptionPasswordSecretName" .Values.otmm.console.cookieEncryptionPasswordSecretName -}}
{{- $_ := required "MicroTx console requires commonConfiguration.externalURL.protocol" .Values.otmm.commonConfiguration.externalURL.protocol -}}
{{- $_ := required "MicroTx console requires commonConfiguration.externalURL.host" .Values.otmm.commonConfiguration.externalURL.host -}}
{{- end -}}
{{- end -}}
