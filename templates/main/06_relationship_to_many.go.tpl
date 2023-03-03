{{- if or .Table.IsJoinTable .Table.IsView -}}
{{- else -}}
	{{- range $rel := .Table.ToManyRelationships -}}
		{{- $ltable := $.Aliases.Table $rel.Local.Table -}}
		{{- $ftable := $.Aliases.Table $rel.Foreign.Table -}}
		{{- $relAlias := $.Aliases.ManyRelationship $rel.Foreign.Table $rel.Name $rel.JoinTable $rel.JoinLocal.FKeyName -}}
		{{- $schemaForeignTable := .Foreign.Table | $.SchemaTable -}}
// {{$relAlias.Local}} retrieves all the {{.Foreign.Table | singular}}'s {{$ftable.UpPlural}} with an executor
{{- if not (eq $relAlias.Local $ftable.UpPlural)}} via{{range $fcol := $rel.Foreign.Columns}} {{$fcol}}{{end}} columns{{end}}.
func (o *{{$ltable.UpSingular}}) {{$relAlias.Local}}(mods ...qm.QueryMod) {{$ftable.DownSingular}}Query {
	var queryMods []qm.QueryMod
	if len(mods) != 0 {
		queryMods = append(queryMods, mods...)
	}

		{{if $rel.ToJoinTable -}}
	queryMods = append(queryMods,
		{{$schemaJoinTable := $rel.JoinTable | $.SchemaTable -}}
		qm.InnerJoin("
			{{- $schemaJoinTable}} ON
			{{- range $idx, $fcol := $rel.Foreign.Columns -}}
				{{- if $idx}} AND {{end -}}
				{{$schemaForeignTable}}.{{$fcol | $.Quotes}} = {{$schemaJoinTable}}.{{index $rel.JoinForeign.Columns $idx | $.Quotes -}}
			{{- end }}
		"),
		{{range $idx, $fcol := $rel.JoinLocal.Columns -}}
		qm.Where("{{$schemaJoinTable}}.{{$fcol | $.Quotes}}=?", o.{{$ltable.Column (index $rel.Local.Columns $idx)}}),
		{{end -}}
	)
		{{else -}}
	queryMods = append(queryMods,
		{{- range $idx, $fcol := $rel.Foreign.Columns -}}
		qm.Where("{{$schemaForeignTable}}.{{$fcol | $.Quotes}}=?", o.{{$ltable.Column (index $rel.Local.Columns $idx)}}),
		{{- end }}
	)
		{{end}}

	return {{$ftable.UpPlural}}(queryMods...)
}

{{end -}}{{- /* range relationships */ -}}
{{- end -}}{{- /* if isJoinTable */ -}}
