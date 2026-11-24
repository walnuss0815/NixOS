{{- range . }}{{- range .Vulnerabilities }}
{{ .Severity }}	{{ .VulnerabilityID }}	{{ .PkgName }}	{{ .InstalledVersion }}	{{ .FixedVersion }}	{{ .Status }}
{{- end }}{{- end }}
