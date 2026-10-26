{{- define "sv.labels" -}}
app.kubernetes.io/name: smart-vineyard
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "sv.secretEnv" -}}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ .secret }}
      key: {{ .key }}
{{- if .optional }}
      optional: true
{{- end }}
{{- end }}

{{/* Environment shared by web and worker */}}
{{- define "sv.appEnv" -}}
- name: RAILS_ENV
  value: production
- name: RAILS_LOG_TO_STDOUT
  value: "true"
- name: APP_HOST
  value: {{ .Values.host | quote }}
- name: DB_HOST
  value: {{ printf "%s-postgres" .Release.Name | quote }}
- name: REDIS_URL
  value: {{ printf "redis://%s-redis:6379/1" .Release.Name | quote }}
{{- $s := .Values.existingSecret }}
{{- range $env, $key := dict "DB_NAME" "db-name" "DB_USER" "db-user" "DB_PASSWORD" "db-password" "SECRET_KEY_BASE" "secret-key-base" "SMTP_ADDRESS" "smtp-address" "SMTP_PORT" "smtp-port" "SMTP_DOMAIN" "smtp-domain" "SMTP_USER_NAME" "smtp-user-name" "SMTP_PASSWORD" "smtp-password" "MAILER_SENDER" "mailer-sender" }}
{{ include "sv.secretEnv" (dict "name" $env "secret" $s "key" $key) }}
{{- end }}
{{ include "sv.secretEnv" (dict "name" "YANDEX_MAPS_API_KEY" "secret" $s "key" "yandex-maps-api-key" "optional" true) }}
{{- end }}

{{- define "sv.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end }}
