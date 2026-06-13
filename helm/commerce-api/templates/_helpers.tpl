{{/*
=============================================================================
_helpers.tpl — Named template library for the commerce-api chart
=============================================================================
All named templates are prefixed with "commerce-api." to avoid collisions
if this chart is used as a subchart or alongside other charts in the same
Helm release context.

Convention:
  - Use {{ include "commerce-api.X" . }} (not {{ template }}) so the result
    can be piped to indent/nindent functions.
  - Templates that produce label maps use nindent 4 to match the indentation
    expected at the call site in resource metadata blocks.
=============================================================================
*/}}

{{/*
Expand the name of the chart.
nameOverride truncates at 63 characters per Kubernetes naming constraints.
*/}}
{{- define "commerce-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a fully qualified app name.
If fullnameOverride is set, it is used verbatim (truncated to 63 chars).
Otherwise: <release-name>-<chart-name>, also truncated.
The release name is included to allow multiple releases of the same chart
in the same namespace (e.g., commerce-api-blue and commerce-api-green).
*/}}
{{- define "commerce-api.fullname" -}}
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
Create chart label value: <chart-name>-<chart-version>
Used in the helm.sh/chart label for traceability.
*/}}
{{- define "commerce-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to every resource created by this chart.
These follow the recommended Kubernetes label schema:
https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/
*/}}
{{- define "commerce-api.labels" -}}
helm.sh/chart: {{ include "commerce-api.chart" . }}
{{ include "commerce-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels — used in Deployment spec.selector.matchLabels and Service spec.selector.
WARNING: selector labels are immutable on Deployments once created.
Do NOT add labels here that might change between releases.
*/}}
{{- define "commerce-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "commerce-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name resolution.
If serviceAccount.create is true, use the fullname unless serviceAccount.name is set.
If serviceAccount.create is false, use serviceAccount.name (must reference an existing SA).
*/}}
{{- define "commerce-api.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "commerce-api.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference — combines repository and tag.
If image.tag is empty, falls back to .Chart.AppVersion.
This ensures that omitting tag in values still produces a valid image reference.
*/}}
{{- define "commerce-api.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion }}
{{- printf "%s:%s" .Values.image.repository $tag }}
{{- end }}

{{/*
ConfigMap name — derived from fullname for consistent referencing across templates.
*/}}
{{- define "commerce-api.configMapName" -}}
{{- printf "%s-config" (include "commerce-api.fullname" .) }}
{{- end }}

{{/*
Secret name — derived from fullname.
*/}}
{{- define "commerce-api.secretName" -}}
{{- printf "%s-secret" (include "commerce-api.fullname" .) }}
{{- end }}
