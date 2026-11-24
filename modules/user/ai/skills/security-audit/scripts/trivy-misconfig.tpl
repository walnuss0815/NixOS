{{- range . }}{{- $target := .Target }}{{- range .Misconfigurations }}
{{ .ID }}	{{ .Severity }}	{{ .Title }}	{{ $target }}	{{ .CauseMetadata.StartLine }}
{{- end }}{{- end }}
