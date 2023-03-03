{{- if or .Table.IsJoinTable .Table.IsView -}}
{{- else -}}
	{{- range $fkey := .Table.FKeys -}}
		{{- $ltable := $.Aliases.Table $fkey.Local.Table -}}
		{{- $ftable := $.Aliases.Table $fkey.Foreign.Table -}}
		{{- $rel := $ltable.Relationship $fkey.Name -}}
		{{- $arg := printf "maybe%s" $ltable.UpSingular -}}
		{{- $schemaTable := $fkey.Local.Table | $.SchemaTable }}
{{if $.AddGlobal -}}
// Set{{$rel.Foreign}}G of the {{$ltable.DownSingular}} to the related item.
// Sets o.R.{{$rel.Foreign}} to related.
{{- if not $.NoBackReferencing}}
// Adds o to related.R.{{$rel.Local}}.
{{- end}}
// Uses the global database handle.
func (o *{{$ltable.UpSingular}}) Set{{$rel.Foreign}}G({{if not $.NoContext}}ctx context.Context, {{end -}} insert bool, related *{{$ftable.UpSingular}}) error {
	return o.Set{{$rel.Foreign}}({{if $.NoContext}}boil.GetDB(){{else}}ctx, boil.GetContextDB(){{end}}, insert, related)
}

{{end -}}

{{if $.AddPanic -}}
// Set{{$rel.Foreign}}P of the {{$ltable.DownSingular}} to the related item.
// Sets o.R.{{$rel.Foreign}} to related.
{{- if not $.NoBackReferencing}}
// Adds o to related.R.{{$rel.Local}}.
{{- end}}
// Panics on error.
func (o *{{$ltable.UpSingular}}) Set{{$rel.Foreign}}P({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, insert bool, related *{{$ftable.UpSingular}}) {
	if err := o.Set{{$rel.Foreign}}({{if not $.NoContext}}ctx, {{end -}} exec, insert, related); err != nil {
		panic(boil.WrapErr(err))
	}
}

{{end -}}

{{if and $.AddGlobal $.AddPanic -}}
// Set{{$rel.Foreign}}GP of the {{$ltable.DownSingular}} to the related item.
// Sets o.R.{{$rel.Foreign}} to related.
{{- if not $.NoBackReferencing}}
// Adds o to related.R.{{$rel.Local}}.
{{- end}}
// Uses the global database handle and panics on error.
func (o *{{$ltable.UpSingular}}) Set{{$rel.Foreign}}GP({{if not $.NoContext}}ctx context.Context, {{end -}} insert bool, related *{{$ftable.UpSingular}}) {
	if err := o.Set{{$rel.Foreign}}({{if $.NoContext}}boil.GetDB(){{else}}ctx, boil.GetContextDB(){{end}}, insert, related); err != nil {
		panic(boil.WrapErr(err))
	}
}

{{end -}}

// Set{{$rel.Foreign}} of the {{$ltable.DownSingular}} to the related item.
// Sets o.R.{{$rel.Foreign}} to related.
{{- if not $.NoBackReferencing}}
// Adds o to related.R.{{$rel.Local}}.
{{- end}}
func (o *{{$ltable.UpSingular}}) Set{{$rel.Foreign}}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, insert bool, related *{{$ftable.UpSingular}}) error {
	var err error
	if insert {
		if err = related.Insert({{if not $.NoContext}}ctx, {{end -}} exec, boil.Infer()); err != nil {
			return errors.Wrap(err, "failed to insert into foreign table")
		}
	}

	updateQuery := fmt.Sprintf(
		"UPDATE {{$schemaTable}} SET %s WHERE %s",
		strmangle.SetParamNames("{{$.LQ}}", "{{$.RQ}}", {{if $.Dialect.UseIndexPlaceholders}}1{{else}}0{{end}}, []string{{"{"}}{{$fkey.Local.Columns | stringMap .StringFuncs.quoteWrap | join ", "}}{{"}"}}),
		strmangle.WhereClause("{{$.LQ}}", "{{$.RQ}}", {{if $.Dialect.UseIndexPlaceholders}}{{intAdd (len $fkey.Local.Columns) 1}}{{else}}0{{end}}, {{$ltable.DownSingular}}PrimaryKeyColumns),
	)
	values := []interface{}{
		{{- range $idx, $fcol := .Foreign.Columns -}}related.{{$ftable.Column $fcol}}, {{- end -}}
		o.{{$.Table.PKey.Columns | stringMap (aliasCols $ltable) | join ", o."}}
	{{- "}"}}

	{{if $.NoContext -}}
	if boil.DebugMode {
		fmt.Fprintln(boil.DebugWriter, updateQuery)
		fmt.Fprintln(boil.DebugWriter, values)
	}
	{{else -}}
	if boil.IsDebug(ctx) {
		writer := boil.DebugWriterFrom(ctx)
		fmt.Fprintln(writer, updateQuery)
		fmt.Fprintln(writer, values)
	}
	{{end -}}

	{{if $.NoContext -}}
	if _, err = exec.Exec(updateQuery, values...); err != nil {
		return errors.Wrap(err, "failed to update local table")
	}
	{{- else -}}
	if _, err = exec.ExecContext(ctx, updateQuery, values...); err != nil {
		return errors.Wrap(err, "failed to update local table")
	}
	{{- end}}

	{{range $idx, $lcol := $fkey.Local.Columns -}}
		{{- $fcol := index $fkey.Foreign.Columns $idx -}}
		{{- $lprop := $ltable.Column $lcol -}}
		{{- $fprop := $ftable.Column $fcol -}}
		{{- if usesPrimitives $.Tables $fkey.Local.Table $lcol $fkey.Foreign.Table $fcol -}}
			o.{{$lprop}} = related.{{$fprop}}
		{{- else}}
			queries.Assign(&o.{{$lprop}}, related.{{$fprop}})
		{{- end}}
	{{end}}

	if o.R == nil {
		o.R = &{{$ltable.DownSingular}}R{
			{{$rel.Foreign}}: related,
		}
	} else {
		o.R.{{$rel.Foreign}} = related
	}

	{{if not $.NoBackReferencing -}}
	{{if $fkey.Local.Unique -}}
	if related.R == nil {
		related.R = &{{$ftable.DownSingular}}R{
			{{$rel.Local}}: o,
		}
	} else {
		related.R.{{$rel.Local}} = o
	}
	{{else -}}
	if related.R == nil {
		related.R = &{{$ftable.DownSingular}}R{
			{{$rel.Local}}: {{$ltable.UpSingular}}Slice{{"{"}}o{{"}"}},
		}
	} else {
		related.R.{{$rel.Local}} = append(related.R.{{$rel.Local}}, o)
	}
	{{- end}}
	{{- end}}

	return nil
}

		{{- if $fkey.Local.Nullable}}
{{if $.AddGlobal -}}
// Remove{{$rel.Foreign}}G relationship.
// Sets o.R.{{$rel.Foreign}} to nil.
{{- if not $.NoBackReferencing}}
// Removes o from all passed in related items' relationships struct.
{{- end}}
// Uses the global database handle.
func (o *{{$ltable.UpSingular}}) Remove{{$rel.Foreign}}G({{if not $.NoContext}}ctx context.Context, {{end -}} related *{{$ftable.UpSingular}}) error {
	return o.Remove{{$rel.Foreign}}({{if $.NoContext}}boil.GetDB(){{else}}ctx, boil.GetContextDB(){{end}}, related)
}

{{end -}}

{{if $.AddPanic -}}
// Remove{{$rel.Foreign}}P relationship.
// Sets o.R.{{$rel.Foreign}} to nil.
{{- if not $.NoBackReferencing}}
// Removes o from all passed in related items' relationships struct.
{{- end}}
// Panics on error.
func (o *{{$ltable.UpSingular}}) Remove{{$rel.Foreign}}P({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, related *{{$ftable.UpSingular}}) {
	if err := o.Remove{{$rel.Foreign}}({{if not $.NoContext}}ctx, {{end -}} exec, related); err != nil {
		panic(boil.WrapErr(err))
	}
}

{{end -}}

{{if and $.AddGlobal $.AddPanic -}}
// Remove{{$rel.Foreign}}GP relationship.
// Sets o.R.{{$rel.Foreign}} to nil.
{{- if not $.NoBackReferencing}}
// Removes o from all passed in related items' relationships struct.
{{- end}}
// Uses the global database handle and panics on error.
func (o *{{$ltable.UpSingular}}) Remove{{$rel.Foreign}}GP({{if not $.NoContext}}ctx context.Context, {{end -}} related *{{$ftable.UpSingular}}) {
	if err := o.Remove{{$rel.Foreign}}({{if $.NoContext}}boil.GetDB(){{else}}ctx, boil.GetContextDB(){{end}}, related); err != nil {
		panic(boil.WrapErr(err))
	}
}

{{end -}}

// Remove{{$rel.Foreign}} relationship.
// Sets o.R.{{$rel.Foreign}} to nil.
{{- if not $.NoBackReferencing}}
// Removes o from all passed in related items' relationships struct.
{{- end}}
func (o *{{$ltable.UpSingular}}) Remove{{$rel.Foreign}}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, related *{{$ftable.UpSingular}}) error {
	var err error

	{{range $lcol := $fkey.Local.Columns -}}
	queries.SetScanner(&o.{{$ltable.Column $lcol}}, nil)
	{{end}}
	{{if $.NoContext -}}
	if {{if not $.NoRowsAffected}}_, {{end -}} err = o.Update(exec, boil.Whitelist({{$fkey.Local.Columns | stringMap .StringFuncs.quoteWrap | join ", "}})); err != nil {
	{{else -}}
	if {{if not $.NoRowsAffected}}_, {{end -}} err = o.Update(ctx, exec, boil.Whitelist({{$fkey.Local.Columns | stringMap .StringFuncs.quoteWrap | join ", "}})); err != nil {
	{{end -}}
		return errors.Wrap(err, "failed to update local table")
	}

	if o.R != nil {
		o.R.{{$rel.Foreign}} = nil
	}
	if related == nil || related.R == nil {
		return nil
	}

	{{if not $.NoBackReferencing -}}
	{{if $fkey.Local.Unique -}}
	related.R.{{$rel.Local}} = nil
	{{else -}}
	for i, ri := range related.R.{{$rel.Local}} {
		if {{range $idx, $lcol := $fkey.Local.Columns -}}
			{{- if $idx}} && {{end -}}
			{{- $fcol := index $fkey.Foreign.Columns $idx -}}
			{{- $lprop := $ltable.Column $lcol -}}
			{{- if usesPrimitives $.Tables $fkey.Local.Table $lcol $fkey.Foreign.Table $fcol -}}
				(o.{{$lprop}} == ri.{{$lprop}})
			{{- else -}}
				queries.Equal(o.{{$lprop}}, ri.{{$lprop}})
			{{- end -}}
		{{- end}} {
			ln := len(related.R.{{$rel.Local}})
			if ln > 1 && i < ln-1 {
				related.R.{{$rel.Local}}[i] = related.R.{{$rel.Local}}[ln-1]
			}
			related.R.{{$rel.Local}} = related.R.{{$rel.Local}}[:ln-1]
			break
		}
	}
	{{end -}}
	{{end -}}

	return nil
}
{{end -}}{{/* if foreignkey nullable */}}
{{- end -}}{{/* range */}}
{{- end -}}{{/* join table */}}
