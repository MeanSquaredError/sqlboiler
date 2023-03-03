{{- if or .Table.IsJoinTable .Table.IsView -}}
{{- else -}}
	{{- range $fkey := .Table.FKeys -}}
		{{- $ltable := $.Aliases.Table $fkey.Local.Table -}}
		{{- $ftable := $.Aliases.Table $fkey.Foreign.Table -}}
		{{- $rel := $ltable.Relationship $fkey.Name -}}
		{{- $arg := printf "maybe%s" $ltable.UpSingular -}}
		{{- $canSoftDelete := (getTable $.Tables $fkey.Foreign.Table).CanSoftDelete $.AutoColumns.Deleted }}
// Load{{$rel.Foreign}} allows an eager lookup of values, cached into the
// loaded structs of the objects. This is for an N-1 relationship.
func ({{$ltable.DownSingular}}L) Load{{$rel.Foreign}}({{if $.NoContext}}e boil.Executor{{else}}ctx context.Context, e boil.ContextExecutor{{end}}, singular bool, {{$arg}} interface{}, mods queries.Applicator) error {
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
		{{- $nonPrimitives := fkNonPrimitiveIndexes $.Tables $fkey}}
		{{- if $nonPrimitives}}
			if {{range $idx := $nonPrimitives -}}
				{{- if $idx}} && {{end -}}
				{{- $lcol := index $fkey.Local.Columns $idx -}}
				!queries.IsNil(object.{{$ltable.Column $lcol}})
			{{- end}} {
				args = append(args{{- range $lcol := $fkey.Local.Columns}}, object.{{$ltable.Column $lcol}}{{end}})
			}
		{{- else}}
			args = append(args{{- range $lcol := $fkey.Local.Columns}}, object.{{$ltable.Column $lcol}}{{end}})
		{{- end}}
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
			for i := 0; i < len(args); i += {{len $fkey.Local.Columns}} {
				if {{range $idx, $lcol := $fkey.Local.Columns -}}
					{{- if $idx}} && {{end -}}
					{{- $fcol := index $fkey.Foreign.Columns $idx -}}
					{{- $lprop := $ltable.Column $lcol -}}
					{{- if usesPrimitives $.Tables $fkey.Local.Table $lcol $fkey.Foreign.Table $fcol -}}
						(args[i+{{$idx}}] == obj.{{$lprop}})
					{{- else -}}
						queries.Equal(args[i+{{$idx}}], obj.{{$lprop}})
					{{- end -}}
				{{- end }} {
					continue Outer
				}
			}
			{{- $nonPrimitives := fkNonPrimitiveIndexes $.Tables $fkey}}
			{{- if $nonPrimitives}}
				if {{range $idx := $nonPrimitives -}}
					{{- if $idx}} && {{end -}}
					{{- $lcol := index $fkey.Local.Columns $idx -}}
					!queries.IsNil(object.{{$ltable.Column $lcol}})
				{{- end}} {
					args = append(args{{- range $lcol := $fkey.Local.Columns}}, obj.{{$ltable.Column $lcol}}{{end}})
				}
			{{- else}}
				args = append(args{{- range $lcol := $fkey.Local.Columns}}, obj.{{$ltable.Column $lcol}}{{end}})
			{{- end}}
		}
	}

	if len(args) == 0 {
		return nil
	}

	{{if ne (len $fkey.Foreign.Columns) 1 -}}
	where := ""
	for i, n := 0, len(args); i < n; i += {{len $fkey.Foreign.Columns}} {
		if i != 0 {
			where += " OR "
		}
		where += "(
		{{- range $idx, $fcol := $fkey.Foreign.Columns -}}
			{{- if $idx}} AND {{end -}}
			{{- if $.Dialect.UseSchema}}{{$.Schema}}.{{end}}{{$fkey.Foreign.Table}}.{{$fcol}} = ?
		{{- end -}}
		)"
	}
	{{- end}}
	query := NewQuery(
		qm.From(`{{if $.Dialect.UseSchema}}{{$.Schema}}.{{end}}{{.Foreign.Table}}`),
		{{if eq (len $fkey.Foreign.Columns) 1 -}}
		qm.WhereIn(`{{if $.Dialect.UseSchema}}{{$.Schema}}.{{end}}{{$fkey.Foreign.Table}}.{{index $fkey.Foreign.Columns 0}} in ?`, args...),
		{{- else -}}
		qm.Where(where, args...),
		{{- end}}
		{{if and $.AddSoftDeletes $canSoftDelete -}}
		qmhelper.WhereIsNull(`{{if $.Dialect.UseSchema}}{{$.Schema}}.{{end}}{{.Foreign.Table}}.{{or $.AutoColumns.Deleted "deleted_at"}}`),
		{{- end}}
    )
	if mods != nil {
		mods.Apply(query)
	}

	{{if $.NoContext -}}
	results, err := query.Query(e)
	{{else -}}
	results, err := query.QueryContext(ctx, e)
	{{end -}}
	if err != nil {
		return errors.Wrap(err, "failed to eager load {{$ftable.UpSingular}}")
	}

	var resultSlice []*{{$ftable.UpSingular}}
	if err = queries.Bind(results, &resultSlice); err != nil {
		return errors.Wrap(err, "failed to bind eager loaded slice {{$ftable.UpSingular}}")
	}

	if err = results.Close(); err != nil {
		return errors.Wrap(err, "failed to close results of eager load for {{.Foreign.Table}}")
	}
	if err = results.Err(); err != nil {
		return errors.Wrap(err, "error occurred during iteration of eager loaded relations for {{.Foreign.Table}}")
	}

	{{if not $.NoHooks -}}
	if len({{$ftable.DownSingular}}AfterSelectHooks) != 0 {
		for _, obj := range resultSlice {
			if err := obj.doAfterSelectHooks({{if $.NoContext}}e{{else}}ctx, e{{end}}); err != nil {
				return err
			}
		}
	}
	{{- end}}

	if len(resultSlice) == 0 {
		return nil
	}

	if singular {
		foreign := resultSlice[0]
		object.R.{{$rel.Foreign}} = foreign
		{{if not $.NoBackReferencing -}}
		if foreign.R == nil {
			foreign.R = &{{$ftable.DownSingular}}R{}
		}
			{{if $fkey.Local.Unique -}}
		foreign.R.{{$rel.Local}} = object
			{{else -}}
		foreign.R.{{$rel.Local}} = append(foreign.R.{{$rel.Local}}, object)
			{{end -}}
		{{end -}}
		return nil
	}

	for _, local := range slice {
		for _, foreign := range resultSlice {
			if {{range $idx, $lcol := $fkey.Local.Columns -}}
				{{- if $idx}} && {{end -}}
				{{- $fcol := index $fkey.Foreign.Columns $idx -}}
				{{- $lprop := $ltable.Column $lcol -}}
				{{- $fprop := $ftable.Column $fcol -}}
				{{- if usesPrimitives $.Tables $fkey.Local.Table $lcol $fkey.Foreign.Table $fcol -}}
					local.{{$lprop}} == foreign.{{$fprop}}
				{{- else -}}
					queries.Equal(local.{{$lprop}}, foreign.{{$fprop}})
				{{- end -}}
			{{- end }} {
				local.R.{{$rel.Foreign}} = foreign
				{{if not $.NoBackReferencing -}}
				if foreign.R == nil {
					foreign.R = &{{$ftable.DownSingular}}R{}
				}
					{{if $fkey.Local.Unique -}}
				foreign.R.{{$rel.Local}} = local
					{{else -}}
				foreign.R.{{$rel.Local}} = append(foreign.R.{{$rel.Local}}, local)
					{{end -}}
				{{end -}}
				break
			}
		}
	}

	return nil
}
{{end -}}{{/* range */}}
{{end}}{{/* join table */}}
