{{- if or .Table.IsJoinTable .Table.IsView -}}
{{- else -}}
	{{- range $fkey := .Table.FKeys -}}
		{{- $ltable := $.Aliases.Table $fkey.Local.Table -}}
		{{- $ftable := $.Aliases.Table $fkey.Foreign.Table -}}
		{{- $rel := $ltable.Relationship $fkey.Name -}}
// {{$rel.Foreign}} pointed to by the foreign key.
func (o *{{$ltable.UpSingular}}) {{$rel.Foreign}}(mods ...qm.QueryMod) ({{$ftable.DownSingular}}Query) {
	queryMods := []qm.QueryMod{
		{{- range $idx, $fcol := $fkey.Foreign.Columns -}}
			qm.Where("{{$fcol | $.Quotes}} = ?", o.{{$ltable.Column (index $fkey.Local.Columns $idx)}}),
		{{- end}}
	}

	queryMods = append(queryMods, mods...)

	return {{$ftable.UpPlural}}(queryMods...)
}
{{- end -}}
{{- end -}}
