package drivers

// ToOneRelationship describes a relationship between two tables where the local
// table has no id, and the foreign table has an id that matches a column in the
// local table, that column can also be unique which changes the dynamic into a
// one-to-one style, not a to-many.
type ToOneRelationship struct {
	Name    string          `json:"name"`
	Local	ForeignKeySide	`json:"local"`
	Foreign	ForeignKeySide	`json:"foreign"`
}

// JoinTableSide describes one side (local or foreign) of a join table
type JoinTableSide struct {
	FKeyName string   `json:"fkey_name"`
	Columns  []string `json:"columns"`
	Nullable bool     `json:"nullable"`	// True iff at least one column is nullable
	Unique   bool     `json:"unique"`	// True iff all columns are unique
}

// ToManyRelationship describes a relationship between two tables where the
// local table has no id, and either:
// 1. the foreign table has an id that matches a column in the local table.
// 2. the foreign table has columns that matches the primary key in the local table,
//    in the case of composite foreign keys.
type ToManyRelationship struct {
	Name string `json:"name"`

	Local	ForeignKeySide `json:"local"`
	Foreign	ForeignKeySide `json:"foreign"`

	ToJoinTable bool          `json:"to_join_table"`
	JoinTable   string        `json:"join_table"`
	JoinLocal   JoinTableSide `json:"join_local"`
	JoinForeign JoinTableSide `json:"join_foreign"`
}

// ToOneRelationships relationship lookups
// Input should be the sql name of a table like: videos
func ToOneRelationships(table string, tables []Table) []ToOneRelationship {
	localTable := GetTable(tables, table)
	return toOneRelationships(localTable, tables)
}

// ToManyRelationships relationship lookups
// Input should be the sql name of a table like: videos
func ToManyRelationships(table string, tables []Table) []ToManyRelationship {
	localTable := GetTable(tables, table)
	return toManyRelationships(localTable, tables)
}

func toOneRelationships(table Table, tables []Table) []ToOneRelationship {
	var relationships []ToOneRelationship

	for _, t := range tables {
		for _, f := range t.FKeys {
			if f.Foreign.Table == table.Name && !t.IsJoinTable && f.Local.Unique {
				relationships = append(relationships, buildToOneRelationship(table, f, t, tables))
			}
		}
	}

	return relationships
}

func toManyRelationships(table Table, tables []Table) []ToManyRelationship {
	var relationships []ToManyRelationship

	for _, t := range tables {
		for _, f := range t.FKeys {
			if f.Foreign.Table == table.Name && (t.IsJoinTable || !f.Local.Unique) {
				relationships = append(relationships, buildToManyRelationship(table, f, t, tables))
			}
		}
	}

	return relationships
}

func buildToOneRelationship(localTable Table, foreignKey ForeignKey, foreignTable Table, tables []Table) ToOneRelationship {
	return ToOneRelationship{
		Name: foreignKey.Name,
		Local: ForeignKeySide{
			Table:    localTable.Name,
			Columns:  foreignKey.Foreign.Columns,
			Nullable: foreignKey.Foreign.Nullable,
			Unique:   foreignKey.Foreign.Unique,
		},
		Foreign: ForeignKeySide{
			Table:    foreignTable.Name,
			Columns:  foreignKey.Local.Columns,
			Nullable: foreignKey.Local.Nullable,
			Unique:   foreignKey.Local.Unique,
		},
	}
}

func buildToManyRelationship(localTable Table, foreignKey ForeignKey, foreignTable Table, tables []Table) ToManyRelationship {
	if !foreignTable.IsJoinTable {
		return ToManyRelationship{
			Name:  foreignKey.Name,
			Local: ForeignKeySide{
				Table:    localTable.Name,
				Columns:  foreignKey.Foreign.Columns,
				Nullable: foreignKey.Foreign.Nullable,
				Unique:   foreignKey.Foreign.Unique,
			},
			Foreign: ForeignKeySide{
				Table:    foreignTable.Name,
				Columns:  foreignKey.Local.Columns,
				Nullable: foreignKey.Local.Nullable,
				Unique:   foreignKey.Local.Unique,
			},
			ToJoinTable:    false,
		}
	}

	relationship := ToManyRelationship{
		Local: ForeignKeySide{
			Table:    localTable.Name,
			Columns:  foreignKey.Foreign.Columns,
			Nullable: foreignKey.Foreign.Nullable,
			Unique:   foreignKey.Foreign.Unique,
		},

		ToJoinTable: true,
		JoinTable:   foreignTable.Name,

		JoinLocal: JoinTableSide{
			FKeyName: foreignKey.Name,
			Columns:  foreignKey.Local.Columns,
			Nullable: foreignKey.Local.Nullable,
			Unique:   foreignKey.Local.Unique,
		},
	}

	for _, fk := range foreignTable.FKeys {
		if fk.Name == foreignKey.Name {
			continue
		}
		relationship.JoinForeign = JoinTableSide{
			FKeyName: fk.Name,
			Columns:  fk.Local.Columns,
			Nullable: fk.Local.Nullable,
			Unique:   fk.Local.Unique,
		}
		relationship.Foreign = ForeignKeySide{
			Table:    fk.Foreign.Table,
			Columns:  fk.Foreign.Columns,
			Nullable: fk.Foreign.Nullable,
			Unique:   fk.Foreign.Unique,
		}
	}

	return relationship
}
