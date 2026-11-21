# ADR-0008: Bible translations — what ships in the app and what is imported

Status: Accepted, 2026-11-20. Decisions 1 and 2 made by the owner.

| # | Decision |
|---|---|
| 1 | **Only the Vietnamese 1925 translation (VI1925) is bundled inside the app.** The owner states it is legal and free to use. Its text is taken from the owner's own `bible` database (stored there under the code `VI1934`). |
| 2 | **Every other translation is imported at each church**, from a file or a database that church provides, and stays on that church's Mac. No other translation's text enters the repository or the app bundle. |
| 3 | The repository holds VI1925 as one translation file in the format defined by LIB-004, with metadata recording "approved by the owner, 2026-11-20" and its source. It is the only Bible text committed. |
| 4 | Imported translations are stored in the church's library database, marked with where they came from. The import screen states that the church is responsible for having the right to use what it imports. |
| 5 | Verse numbering is per translation. The 1925 Vietnamese text and the English (KJV-style) numbering differ in 46 chapters; pairing two translations is by reference, and where they disagree the app says so instead of showing a wrong pair. |
| 6 | An English translation to bundle is not chosen. Until one is, English comes only by import. Candidates the scripture research is checking: King James Version, World English Bible. |
| 7 | The importer supports: the LIB-004 JSON format, USFM, and a direct import from a MySQL database with the owner's schema (`versions`, `books`, `verses`). The MySQL import runs as a separate tool so the app itself carries no database client and stores no database password. |

## Consequences

- If the app is ever given to other churches, it carries only VI1925.
- The owner's church can load every version in its database through the importer.
- Copyright status of VI1925 is recorded as the owner's statement. If the app is distributed widely, confirm it for the countries involved.
