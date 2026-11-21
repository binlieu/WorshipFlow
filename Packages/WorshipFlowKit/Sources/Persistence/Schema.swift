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
        return migrator
    }
}
