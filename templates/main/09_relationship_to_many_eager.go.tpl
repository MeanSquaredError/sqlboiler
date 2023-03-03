{{- if or .Table.IsJoinTable .Table.IsView -}}
{{- else -}}
	{{- range $rel := .Table.ToManyRelationships -}}
		{{- $ltable := $.Aliases.Table $rel.Table -}}
		{{- $ftable := $.Aliases.Table $rel.Foreign.Table -}}
		{{- $relAlias := $.Aliases.ManyRelationship $rel.Foreign.Table $rel.Name $rel.JoinTable $rel.JoinLocal.FKeyName -}}
		{{- $arg := printf "maybe%s" $ltable.UpSingular -}}
		{{- $schemaForeignTable := $rel.Foreign.Table | $.SchemaTable -}}
		{{- $canSoftDelete := (getTable $.Tables $rel.Foreign.Table).CanSoftDelete $.AutoColumns.Deleted }}
// Load{{$relAlias.Local}} allows an eager lookup of values, cached into the
// loaded structs of the objects. This is for a 1-M or N-M relationship.
func ({{$ltable.DownSingular}}L) Load{{$relAlias.Local}}({{if $.NoContext}}e boil.Executor{{else}}ctx context.Context, e boil.ContextExecutor{{end}}, singular bool, {{$arg}} interface{}, mods queries.Applicator) error {
	var slice []*{{$ltable.UpSingular}}
	var object *{{$ltable.UpSingular}}

	args := make([]interface{}, 0, 1)
	if singular {
		var ok bool
		object, ok = {{$arg}}.(*{{$ltable.UpSingular}})
		if !ok {
			object = new({{$ltable.UpSingular}})
			ok = queries.SetFromEmbeddedStruct(&object, &{{$arg}})
			if !ok {
				return errors.New(fmt.Sprintf("failed to set %T from embedded struct %T", object, {{$arg}}))
			}
		}
		if object.R == nil {
			object.R = &{{$ltable.DownSingular}}R{}
		}
		args = append(args{{- range $lcol := $rel.Local.Columns}}, object.{{$ltable.Column $lcol}}{{end}})
	} else {
		s, ok := {{$arg}}.(*[]*{{$ltable.UpSingular}})
		if ok {
			slice = *s
		} else {
			ok = queries.SetFromEmbeddedStruct(&slice, {{$arg}})
			if !ok {
				return errors.New(fmt.Sprintf("failed to set %T from embedded struct %T", slice, {{$arg}}))
			}
		}
Outer:
		for _, obj := range slice {
			if obj.R == nil {
				obj.R = &{{$ltable.DownSingular}}R{}
			}

			for i := 0; i < len(args); i += {{len $rel.Local.Columns}} {
				if {{range $idx, $lcol := $rel.Local.Columns -}}
					{{- if $idx}} && {{end -}}
					{{- $fcol := index $rel.Foreign.Columns $idx -}}
					{{- $lprop := $ltable.Column $lcol -}}
					{{- if usesPrimitives $.Tables $rel.Local.Table $lcol $rel.Foreign.Table $fcol -}}
						(args[i+{{$idx}}] == obj.{{$lprop}})
					{{- else -}}
						queries.Equal(args[i+{{$idx}}], obj.{{$lprop}})
					{{- end -}}
				{{- end }} {
					continue Outer
				}
			}

			args = append(args{{- range $lcol := $rel.Local.Columns}}, obj.{{$ltable.Column $lcol}}{{end}})
		}
	}

	if len(args) == 0 {
		return nil
	}

	{{if .ToJoinTable -}}
		{{- $schemaJoinTable := .JoinTable | $.SchemaTable -}}
		{{- $foreignTable := getTable $.Tables .Foreign.Table -}}
	{{if ne (len $rel.JoinLocal.Columns) 1 -}}
	where := ""
	for i, n := 0, len(args); i < n; i += {{len $rel.JoinLocal.Columns}} {
		if i != 0 {
			where += " OR "
		}
		where += "(
		{{- range $idx, $jlcol := $rel.JoinLocal.Columns -}}
			{{- if $idx}} AND {{end -}}
			{{id 0 | $.Quotes}}.{{$jlcol | $.Quotes}} = ?
		{{- end -}}
		)"
	}
	{{- end}}
	query := NewQuery(
		qm.Select("
			{{- $foreignTable.Columns | columnNames | $.QuoteMap | prefixStringSlice (print $schemaForeignTable ".") | join ", " -}},
			{{- .JoinLocal.Columns | $.QuoteMap | prefixStringSlice (print (id 0 | $.Quotes) ".") | join ", " -}},
		"),
		qm.From("{{$schemaForeignTable}}"),
		qm.InnerJoin("{{$schemaJoinTable}} as {{id 0 | $.Quotes}} on {{range $idx, $fcol := $rel.Foreign.Columns -}}
			{{- if $idx}} AND {{end -}}
			{{$schemaForeignTable}}.{{$fcol | $.Quotes}} = {{id 0 | $.Quotes}}.{{index $rel.JoinForeign.Columns $idx | $.Quotes}}
		{{- end -}}"),
		{{if eq (len $rel.Foreign.Columns) 1 -}}
		qm.WhereIn("{{id 0 | $.Quotes}}.{{.JoinLocalColumn | $.Quotes}} in ?", args...),
		{{- else -}}
		qm.Where(where, args...),
		{{- end}}
		{{if and $.AddSoftDeletes $canSoftDelete -}}
		qmhelper.WhereIsNull("{{$schemaForeignTable}}.{{or $.AutoColumns.Deleted "deleted_at" | $.Quotes}}"),
		{{- end}}
	)
		{{else -}}
	{{if ne (len $rel.Foreign.Columns) 1 -}}
	where := ""
	for i, n := 0, len(args); i < n; i += {{len $rel.Foreign.Columns}} {
		if i != 0 {
			where += " OR "
		}
		where += "(
		{{- range $idx, $fcol := $rel.Foreign.Columns -}}
			{{- if $idx}} AND {{end -}}
			{{- if $.Dialect.UseSchema}}{{$.Schema}}.{{end}}{{$rel.Foreign.Table}}.{{$fcol}} = ?
		{{- end -}}
		)"
	}
	{{- end}}
	query := NewQuery(
	    qm.From(`{{if $.Dialect.UseSchema}}{{$.Schema}}.{{end}}{{.Foreign.Table}}`),
		{{if eq (len $rel.Foreign.Columns) 1 -}}
		qm.WhereIn(`{{if $.Dialect.UseSchema}}{{$.Schema}}.{{end}}{{.Foreign.Table}}.{{index $rel.Foreign.Columns 0}} in ?`, args...),
		{{- else -}}
		qm.Where(where, args...),
		{{- end}}
	    {{if and $.AddSoftDeletes $canSoftDelete -}}
	    qmhelper.WhereIsNull(`{{if $.Dialect.UseSchema}}{{$.Schema}}.{{end}}{{.Foreign.Table}}.{{or $.AutoColumns.Deleted "deleted_at"}}`),
	    {{- end}}
    )
		{{end -}}
	if mods != nil {
		mods.Apply(query)
	}

	{{if $.NoContext -}}
	results, err := query.Query(e)
	{{else -}}
	results, err := query.QueryContext(ctx, e)
	{{end -}}
	if err != nil {
		return errors.Wrap(err, "failed to eager load {{.Foreign.Table}}")
	}

	var resultSlice []*{{$ftable.UpSingular}}
	{{if .ToJoinTable -}}
	{{- $foreignTable := getTable $.Tables .Foreign.Table -}}
	{{- $joinTable := getTable $.Tables .JoinTable -}}
	{{- $localCol := $joinTable.GetColumn .JoinLocalColumn}}
	var localJoinCols []{{$localCol.Type}}
	for results.Next() {
		one := new({{$ftable.UpSingular}})
		var localJoinCol {{$localCol.Type}}

		err = results.Scan({{$foreignTable.Columns | columnNames | stringMap (aliasCols $ftable) | prefixStringSlice "&one." | join ", "}}, &localJoinCol)
		if err != nil {
			return errors.Wrap(err, "failed to scan eager loaded results for {{.ForeignTable}}")
		}
		if err = results.Err(); err != nil {
			return errors.Wrap(err, "failed to plebian-bind eager loaded slice {{.ForeignTable}}")
		}

		resultSlice = append(resultSlice, one)
		localJoinCols = append(localJoinCols, localJoinCol)
	}
	{{- else -}}
	if err = queries.Bind(results, &resultSlice); err != nil {
		return errors.Wrap(err, "failed to bind eager loaded slice {{.ForeignTable}}")
	}
	{{- end}}

	if err = results.Close(); err != nil {
		return errors.Wrap(err, "failed to close results in eager load on {{.ForeignTable}}")
	}
	if err = results.Err(); err != nil {
		return errors.Wrap(err, "error occurred during iteration of eager loaded relations for {{.ForeignTable}}")
	}

	{{if not $.NoHooks -}}
	if len({{$ftable.DownSingular}}AfterSelectHooks) != 0 {
		for _, obj := range resultSlice {
			if err := obj.doAfterSelectHooks({{if $.NoContext}}e{{else}}ctx, e{{end -}}); err != nil {
				return err
			}
		}
	}

	{{- end}}
	if singular {
		object.R.{{$relAlias.Local}} = resultSlice
		{{if not $.NoBackReferencing -}}
		for _, foreign := range resultSlice {
			if foreign.R == nil {
				foreign.R = &{{$ftable.DownSingular}}R{}
			}
			{{if .ToJoinTable -}}
			foreign.R.{{$relAlias.Foreign}} = append(foreign.R.{{$relAlias.Foreign}}, object)
			{{else -}}
			foreign.R.{{$relAlias.Foreign}} = object
			{{end -}}
		}
		{{end -}}
		return nil
	}

	{{if .ToJoinTable -}}
	for i, foreign := range resultSlice {
		localJoinCol := localJoinCols[i]
		for _, local := range slice {
			{{if $usesPrimitives -}}
			if local.{{$col}} == localJoinCol {
			{{else -}}
			if queries.Equal(local.{{$col}}, localJoinCol) {
			{{end -}}
				local.R.{{$relAlias.Local}} = append(local.R.{{$relAlias.Local}}, foreign)
				{{if not $.NoBackReferencing -}}
				if foreign.R == nil {
					foreign.R = &{{$ftable.DownSingular}}R{}
				}
				foreign.R.{{$relAlias.Foreign}} = append(foreign.R.{{$relAlias.Foreign}}, local)
				{{end -}}
				break
			}
		}
	}
	{{else -}}
	for _, foreign := range resultSlice {
		for _, local := range slice {
			{{if $usesPrimitives -}}
			if local.{{$col}} == foreign.{{$fcol}} {
			{{else -}}
			if queries.Equal(local.{{$col}}, foreign.{{$fcol}}) {
			{{end -}}
				local.R.{{$relAlias.Local}} = append(local.R.{{$relAlias.Local}}, foreign)
				{{if not $.NoBackReferencing -}}
				if foreign.R == nil {
					foreign.R = &{{$ftable.DownSingular}}R{}
				}
				foreign.R.{{$relAlias.Foreign}} = local
				{{end -}}
				break
			}
		}
	}
	{{end}}

	return nil
}

{{end -}}{{/* range tomany */}}
{{- end -}}{{/* if IsJoinTable */}}
