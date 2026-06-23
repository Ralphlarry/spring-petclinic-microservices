{{/* Common labels applied to every object */}}
{{- define "petclinic.labels" -}}
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* Per-service selector labels. Call with a dict: (dict "name" $name) */}}
{{- define "petclinic.selectorLabels" -}}
app: {{ .name }}
{{- end -}}

{{/* Resolve the image tag for a service: per-service tag overrides global.imageTag */}}
{{- define "petclinic.tag" -}}
{{- .svc.tag | default .root.Values.global.imageTag -}}
{{- end -}}
