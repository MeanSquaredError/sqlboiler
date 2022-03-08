{{- if or .Table.IsJoinTable .Table.IsView -}}
{{- else -}}
	{{- range $fkey := .Table.FKeys -}}
		{{- $ltable := $.Aliases.Table $fkey.Local.Table -}}
		{{- $ftable := $.Aliases.Table $fkey.Foreign.Table -}}
		{{- $rel := $ltable.Relationship $fkey.Name -}}
		{{- $canSoftDelete := (getTable $.Tables $fkey.Foreign.Table).CanSoftDelete $.AutoColumns.Deleted }}
// {{$rel.Foreign}} pointed to by the foreign key.
func (o *{{$ltable.UpSingular}}) {{$rel.Foreign}}(mods ...qm.QueryMod) ({{$ftable.DownSingular}}Query) {
	queryMods := []qm.QueryMod{
		{{- range $idx, $fcol := $fkey.Foreign.Columns -}}
			qm.Where("{{$fcol | $.Quotes}} = ?", o.{{$ltable.Column (index $fkey.Local.Columns $idx)}}),
		{{- end}}
		{{if and $.AddSoftDeletes $canSoftDelete -}}
		qmhelper.WhereIsNull("deleted_at"),
		{{- end}}
	}

	queryMods = append(queryMods, mods...)

	query := {{$ftable.UpPlural}}(queryMods...)
	queries.SetFrom(query.Query, "{{.Foreign.Table | $.SchemaTable}}")

	return query
}
{{- end -}}
{{- end -}}
