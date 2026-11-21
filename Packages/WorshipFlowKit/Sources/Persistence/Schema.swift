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

        // SYS-002: themes, Looks, props, screen profiles and media assets (KI-016).
        migrator.registerMigration("v3") { db in
            try db.create(table: "theme") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("nameFolded", .text).notNull()
                t.column("definition", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "look") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("screens", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "prop") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("imagePath", .text).notNull()
                t.column("bookmark", .blob)
                t.column("frame", .text).notNull()
                t.column("opacity", .double).notNull()
                t.column("isOn", .boolean).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "screenProfile") { t in
                t.column("id", .text).primaryKey()
                t.column("sortOrder", .integer).notNull()
                t.column("name", .text).notNull()
                t.column("role", .text).notNull()
                t.column("destination", .text).notNull()
                t.column("displayID", .integer)
                t.column("isEnabled", .boolean).notNull()
            }
            try db.create(table: "mediaAsset") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("path", .text).notNull().unique()
                t.column("bookmark", .blob)
                t.column("duration", .double)
                t.column("pixelWidth", .integer)
                t.column("pixelHeight", .integer)
                t.column("addedAt", .datetime).notNull()
            }
            try db.create(index: "mediaAsset_on_kind", on: "mediaAsset", columns: ["kind"])
            // No foreign key: the value may be a built-in theme id, which has no row. deleteTheme clears it.
            try db.alter(table: "presentation") { t in
                t.add(column: "themeID", .text)
            }
            try db.create(index: "presentation_on_themeID", on: "presentation", columns: ["themeID"])
        }

        // STAGE-001a: stage layouts and timers. Definitions are JSON text (see `SettingsJSON`).
        migrator.registerMigration("v4") { db in
            try db.create(table: "stageLayout") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("definition", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "showTimer") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("definition", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        // SLIDE-001a: objects on a slide (text boxes, shapes, images) as JSON text; NULL when a slide has none.
        migrator.registerMigration("v5") { db in
            try db.alter(table: "slide") { t in
                t.add(column: "objects", .text)
            }
        }

        // HW-002 / OUT-005: SDI destinations, mirrors and the SDI video mode. One JSON column holds everything a plain
        // display or window profile does not need; it stays NULL for them, so rows written by v5 read unchanged.
        migrator.registerMigration("v6") { db in
            try db.alter(table: "screenProfile") { t in
                t.add(column: "extra", .text)
            }
        }

        // LIB-004b: Bible translations imported into the library (ADR-0008) and their verses. The full-text index over the
        // folded verse text is derived data, created at open when FTS5 exists (see `ScriptureIndex`), not here.
        migrator.registerMigration("v7") { db in
            try db.create(table: "scriptureTranslation") { t in
                t.column("id", .text).primaryKey()
                // The translation file's id ("kjv", "VI1925"). Unique ignoring case.
                t.column("code", .text).notNull().unique().collate(.nocase)
                t.column("name", .text).notNull()
                t.column("language", .text).notNull()
                t.column("abbreviation", .text).notNull()
                t.column("copyright", .text)
                t.column("licence", .text)
                t.column("sourceDescription", .text)
                t.column("isPublicDomain", .boolean).notNull()
                t.column("ownerApprovalJSON", .text)
                t.column("versificationID", .text).notNull()
                t.column("versificationJSON", .text)
                t.column("versificationNote", .text)
                t.column("verseCount", .integer).notNull()
                t.column("importedAt", .datetime).notNull()
            }
            try db.create(table: "scriptureVerse", options: [.withoutRowID]) { t in
                t.column("translationID", .text).notNull().references("scriptureTranslation", onDelete: .cascade)
                t.column("bookOrder", .integer).notNull()
                t.column("chapter", .integer).notNull()
                t.column("verse", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("textFolded", .text).notNull()
                t.primaryKey(["translationID", "bookOrder", "chapter", "verse"])
            }
        }
        // UI-002: a playlist item is a presentation, a section header or a countdown. `kind` and `payload` (small JSON) say which;
        // `presentationID` becomes nullable, which SQLite only allows by rebuilding the table. Existing rows become presentation items.
        migrator.registerMigration("v8") { db in
            try db.create(table: "playlistItem_v8") { t in
                t.column("id", .text).primaryKey()
                t.column("playlistID", .text).notNull().references("playlist", onDelete: .cascade)
                t.column("presentationID", .text).references("presentation", onDelete: .cascade)
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("arrangementID", .text).references("arrangement", onDelete: .setNull)
                t.column("kind", .text).notNull().defaults(to: "presentation")
                t.column("payload", .text)
            }
            try db.execute(sql: """
                INSERT INTO playlistItem_v8 (id, playlistID, presentationID, sortOrder, createdAt, arrangementID, kind, payload)
                SELECT id, playlistID, presentationID, sortOrder, createdAt, arrangementID, 'presentation', NULL FROM playlistItem
                """)
            try db.drop(table: "playlistItem")
            try db.rename(table: "playlistItem_v8", to: "playlistItem")
            try db.create(index: "playlistItem_on_playlistID_sortOrder", on: "playlistItem", columns: ["playlistID", "sortOrder"])
            try db.create(index: "playlistItem_on_presentationID", on: "playlistItem", columns: ["presentationID"])
            try db.create(index: "playlistItem_on_arrangementID", on: "playlistItem", columns: ["arrangementID"])
        }

        // CUE-002a: macros, slide actions, scheduled events, the schedule engine's state and MIDI bindings. Each definition is JSON
        // text with its own `version` (see `CueEngine`). A slide's actions are deleted with the slide; a reflow re-attaches them to the
        // slides whose words did not change (see `LibraryStore.replaceContent`). Rows of the other tables are untouched.
        migrator.registerMigration("v9") { db in
            try db.create(table: "cueMacro") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("definition", .text).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "cueMacro_on_sortOrder", on: "cueMacro", columns: ["sortOrder"])
            try db.create(table: "cueSlideActions") { t in
                t.column("slideID", .text).primaryKey().references("slide", onDelete: .cascade)
                t.column("definition", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "cueScheduledEvent") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("enabled", .boolean).notNull()
                t.column("definition", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            // One row, enforced: the engine's fired-occurrence state and the latest check are written together.
            try db.create(table: "cueScheduleState") { t in
                t.column("id", .integer).primaryKey().check { $0 == 1 }
                t.column("state", .text).notNull()
                t.column("lastCheckedAt", .datetime)
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "cueMIDIBinding") { t in
                t.column("id", .text).primaryKey()
                t.column("definition", .text).notNull()
                t.column("sortOrder", .integer).notNull()
            }
            try db.create(index: "cueMIDIBinding_on_sortOrder", on: "cueMIDIBinding", columns: ["sortOrder"])
        }

        // CUE-002b: the paired devices of the remote control server. A salted hash of each token, never the token. Rows of the
        // other tables are untouched.
        migrator.registerMigration("v10") { db in
            try db.create(table: "remoteToken") { t in
                t.column("id", .text).primaryKey()
                t.column("label", .text).notNull()
                t.column("salt", .blob).notNull()
                t.column("hash", .blob).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastUsed", .datetime)
            }
        }

        return migrator
    }
}
