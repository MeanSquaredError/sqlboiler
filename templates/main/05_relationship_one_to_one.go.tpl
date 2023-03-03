{{- if or .Table.IsJoinTable .Table.IsView -}}
{{- else -}}
	{{- range $rel := .Table.ToOneRelationships -}}
		{{- $ltable := $.Aliases.Table $rel.Local.Table -}}
		{{- $ftable := $.Aliases.Table $rel.Foreign.Table -}}
		{{- $relAlias := $ftable.Relationship $rel.Name -}}
// {{$relAlias.Local}} pointed to by the foreign key.
func (o *{{$ltable.UpSingular}}) {{$relAlias.Local}}(mods ...qm.QueryMod) ({{$ftable.DownSingular}}Query) {
	queryMods := []qm.QueryMod{
		{{- range $idx, $fcol := $rel.Foreign.Columns -}}
			qm.Where("{{$fcol | $.Quotes}} = ?", o.{{$ltable.Column $fcol}}),
		{{- end}}
	}

	queryMods = append(queryMods, mods...)

	return {{$ftable.UpPlural}}(queryMods...)
}
{{- end -}}
{{- end -}}
