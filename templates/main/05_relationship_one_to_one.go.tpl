{{- if or .Table.IsJoinTable .Table.IsView -}}
{{- else -}}
	{{- range $rel := .Table.ToOneRelationships -}}
		{{- $ltable := $.Aliases.Table $rel.LocalTable -}}
		{{- $ftable := $.Aliases.Table $rel.ForeignTable -}}
		{{- $relAlias := $ftable.Relationship $rel.Name -}}
		{{- $canSoftDelete := (getTable $.Tables $rel.ForeignTable).CanSoftDelete $.AutoColumns.Deleted }}
// {{$relAlias.Local}} pointed to by the foreign key.
func (o *{{$ltable.UpSingular}}) {{$relAlias.Local}}(mods ...qm.QueryMod) ({{$ftable.DownSingular}}Query) {
	queryMods := []qm.QueryMod{
		{{- range $idx, $fcol := $rel.ForeignColumns -}}
			qm.Where("{{$fcol | $.Quotes}} = ?", o.{{$ltable.Column $fcol}}),
		{{- end}}
		{{if and $.AddSoftDeletes $canSoftDelete -}}
			qmhelper.WhereIsNull("deleted_at"),
		{{- end}}
	}

	queryMods = append(queryMods, mods...)

	query := {{$ftable.UpPlural}}(queryMods...)
	queries.SetFrom(query.Query, "{{.ForeignTable | $.SchemaTable}}")

	return query
}
{{- end -}}
{{- end -}}
