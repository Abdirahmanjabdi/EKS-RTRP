{{- define "rtrp-app.image" -}}
{{ .global.image.registry }}/{{ .image.repository }}:{{ .global.image.tag }}
{{- end -}}