package drivers

// ToOneRelationship describes a relationship between two tables where the local
// table has no id, and the foreign table has an id that matches a column in the
// local table, that column can also be unique which changes the dynamic into a
// one-to-one style, not a to-many.
type ToOneRelationship struct {
	Name string `json:"name"`

	LocalTable   string     `json:"local_table"`
	LocalColumns []string   `json:"local_columns"`

	ForeignTable   string   `json:"foreign_table"`
	ForeignColumns []string `json:"foreign_columns"`
}

// ToManyRelationship describes a relationship between two tables where the
// local table has no id, and either:
// 1. the foreign table has an id that matches a column in the local table.
// 2. the foreign table has columns that matches the primary key in the local table,
//    in the case of composite foreign keys.
type ToManyRelationship struct {
	Name string `json:"name"`

	LocalTable string            `json:"local_table"`
	LocalColumns []string        `json:"local_columns"`

	ForeignTable   string        `json:"foreign_table"`
	ForeignColumns []string      `json:"foreign_columns"`

	ToJoinTable bool             `json:"to_join_table"`
	JoinTable   string           `json:"join_table"`

	JoinLocalFKeyName string     `json:"join_local_fkey_name"`
	JoinLocalColumns  []string   `json:"join_local_columns"`

	JoinForeignFKeyName string   `json:"join_foreign_fkey_name"`
	JoinForeignColumns  []string `json:"join_foreign_columns"`
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
		Name:         foreignKey.Name,
		LocalTable:   localTable.Name,
		LocalColumns: foreignKey.Foreign.Columns,

		ForeignTable:   foreignTable.Name,
		ForeignColumns: foreignKey.Local.Columns,
	}
}

func buildToManyRelationship(localTable Table, foreignKey ForeignKey, foreignTable Table, tables []Table) ToManyRelationship {
	if !foreignTable.IsJoinTable {
		return ToManyRelationship{
			Name:           foreignKey.Name,
			LocalTable:     localTable.Name,
			LocalColumns:   foreignKey.Foreign.Columns,
			ForeignTable:   foreignTable.Name,
			ForeignColumns: foreignKey.Local.Columns,
			ToJoinTable:    false,
		}
	}

	relationship := ToManyRelationship{
		LocalTable:   localTable.Name,
		LocalColumns: foreignKey.Foreign.Columns,

		ToJoinTable: true,
		JoinTable:   foreignTable.Name,

		JoinLocalFKeyName: foreignKey.Name,
		JoinLocalColumns:  foreignKey.Local.Columns,
	}

	for _, fk := range foreignTable.FKeys {
		if fk.Name == foreignKey.Name {
			continue
		}

		relationship.JoinForeignFKeyName = fk.Name
		relationship.JoinForeignColumns = fk.Local.Columns

		relationship.ForeignTable = fk.Foreign.Table
		relationship.ForeignColumns = fk.Foreign.Columns
	}

	return relationship
}
