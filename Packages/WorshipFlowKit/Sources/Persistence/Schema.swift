// SYS-001: schema migrations. Named migrations are never edited after release (ADR-0004 decision 6).
import GRDB

enum Schema {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // No eraseDatabaseOnSchemaChange, in any build configuration.

        migrator.registerMigration("v1") { db in
            try db.create(table: "library") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "presentation") { t in
                t.column("id", .text).primaryKey()
                t.column("libraryID", .text).notNull().references("library", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("titleFolded", .text).notNull().defaults(to: "")
                t.column("bodyFolded", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "presentation_on_libraryID", on: "presentation", columns: ["libraryID"])
            try db.create(table: "slide") { t in
                t.column("id", .text).primaryKey()
                t.column("presentationID", .text).notNull().references("presentation", onDelete: .cascade)
                t.column("sortOrder", .integer).notNull()
                t.column("primaryText", .text).notNull()
                t.column("secondaryText", .text)
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "slide_on_presentationID_sortOrder", on: "slide", columns: ["presentationID", "sortOrder"])
            try db.create(table: "playlist") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "playlistItem") { t in
                t.column("id", .text).primaryKey()
                t.column("playlistID", .text).notNull().references("playlist", onDelete: .cascade)
                t.column("presentationID", .text).notNull().references("presentation", onDelete: .cascade)
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "playlistItem_on_playlistID_sortOrder", on: "playlistItem", columns: ["playlistID", "sortOrder"])
            try db.create(index: "playlistItem_on_presentationID", on: "playlistItem", columns: ["presentationID"])
            try db.create(table: "appState") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        // SLIDE-003: song sections and arrangements. Existing slides stay ungrouped.
        migrator.registerMigration("v2") { db in
            try db.create(table: "slideGroup") { t in
                t.column("id", .text).primaryKey()
                t.column("presentationID", .text).notNull().references("presentation", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("sortOrder", .integer).notNull()
            }
            try db.create(index: "slideGroup_on_presentationID_sortOrder", on: "slideGroup",
                          columns: ["presentationID", "sortOrder"])
            try db.create(table: "arrangement") { t in
                t.column("id", .text).primaryKey()
                t.column("presentationID", .text).notNull().references("presentation", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "arrangement_on_presentationID", on: "arrangement", columns: ["presentationID"])
            try db.create(table: "arrangementItem") { t in
                t.column("arrangementID", .text).notNull().references("arrangement", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("groupID", .text).notNull().references("slideGroup", onDelete: .cascade)
                t.primaryKey(["arrangementID", "position"])
            }
            try db.create(index: "arrangementItem_on_groupID", on: "arrangementItem", columns: ["groupID"])
            try db.alter(table: "slide") { t in
                t.add(column: "groupID", .text).references("slideGroup", onDelete: .setNull)
            }
            try db.create(index: "slide_on_groupID", on: "slide", columns: ["groupID"])
            try db.alter(table: "playlistItem") { t in
                t.add(column: "arrangementID", .text).references("arrangement", onDelete: .setNull)
            }
            try db.create(index: "playlistItem_on_arrangementID", on: "playlistItem", columns: ["arrangementID"])
        }
        return migrator
    }
}
