# LIB-004: scripture engine (references, verse slides, translation files, search)

Catalogue: PRES-09 (Bible integration), PRES-10 (two translations side by side). Phase 4. Rules half only: no interface, no persistence, no network, and **no Bible text in the repository** (the tests carry 11 King James Version verses as fixtures; nothing else).

Verification level: Implemented; Unit Tested. Not Simulated in the app; nothing here is wired into the app yet.

Code: `Packages/WorshipFlowKit/Sources/ScriptureEngine` (Foundation and `Domain` only). Tests: `Tests/ScriptureEngineTests`.

## Canon and versification

`Canon.books` lists the 66 books in Protestant order with USFM-style ids (`GEN` ... `REV`, `1SA`, `3JN`) and the KJV verse count of every chapter: 1,189 chapters, 31,102 verses (Old Testament 23,145, New Testament 7,957). Tests check the totals, every per-book total, and the chapters named in the report.

A **versification** (`Versification`) is the table of chapters and verses for one translation, because boundaries differ between translations. Each chapter has a `count` (verses that exist) and a `highest` verse number (larger than `count` when the numbering has a gap). Validation uses `highest`.

Built in: `Versification.kjv` and `Versification.vi1925` (1,189 chapters, 31,081 verses), the latter taken from the owner's database export (counts only). `Versification.differences(a, b)` lists the chapters that differ. A translation file names its table in `metadata.versification` ("KJV" by default). If the text numbers verses past that table (modern English Bibles have a 15th verse in 3 John, the KJV has 14), the verses are kept, the translation's own table is widened, and the loader reports how many.

### Known differences, KJV and VI1925 (46 chapters)

Pairing a KJV slide with a 1925 slide is **by book, chapter and verse number** (see "Slides"). In these chapters the same number can mean different verses, or exist on one side only. No attempt is made to align by content in this slice.

| Chapter | KJV verses | VI1925 verses |
|---|---|---|
| Exodus 12 | 51 | 50 |
| Numbers 29 | 40 | 39 |
| Numbers 30 | 16 | 17 |
| 1 Samuel 20 | 42 | 43 |
| 1 Samuel 23 | 29 | 28 |
| 1 Samuel 24 | 22 | 23 |
| 1 Kings 6 | 38 | 37 |
| 1 Kings 22 | 53 | 54 |
| 2 Kings 2 | 25 | 24 |
| 2 Kings 19 | 37 | 36 |
| 1 Chronicles 8 | 40 | 36 (highest 40) |
| 2 Chronicles 35 | 27 | 26 |
| Esther 1 | 22 | 21 (highest 22) |
| Job 38 | 41 | 38 |
| Job 39 | 30 | 38 |
| Job 40 | 24 | 28 |
| Job 41 | 34 | 25 |
| Isaiah 8 | 22 | 23 |
| Isaiah 9 | 21 | 20 |
| Ezekiel 20 | 49 | 44 |
| Ezekiel 21 | 32 | 37 |
| Hosea 11 | 12 | 11 |
| Hosea 12 | 14 | 15 |
| Amos 1 | 15 | 14 |
| Jonah 1 | 17 | 16 |
| Jonah 2 | 10 | 11 |
| Micah 4 | 13 | 14 |
| Micah 5 | 15 | 14 |
| Matthew 17 | 27 | 26 (highest 27) |
| Matthew 18 | 35 | 34 (highest 35) |
| Matthew 23 | 39 | 38 (highest 39) |
| Mark 7 | 37 | 36 (highest 37) |
| Mark 9 | 50 | 49 (highest 51) |
| Mark 10 | 52 | 53 |
| Mark 11 | 33 | 32 (highest 33) |
| Mark 15 | 47 | 46 (highest 47) |
| Luke 17 | 37 | 36 (highest 37) |
| Luke 23 | 56 | 55 (highest 56) |
| Acts 8 | 40 | 39 (highest 40) |
| Acts 15 | 41 | 40 (highest 41) |
| Acts 24 | 27 | 26 (highest 27) |
| Acts 28 | 31 | 30 (highest 31) |
| 1 Corinthians 3 | 23 | 22 |
| 2 Corinthians 13 | 14 | 13 |
| 3 John 1 | 14 | 15 |
| Revelation 12 | 17 | 18 |

(Totals: KJV 31,102; VI1925 31,081. In the VI1925 chapters marked "highest", some verse numbers are skipped; the table does not say which.)

The KJV table was checked against two independent sources: the "NKJV" column of the owner's export (identical in all 1,189 chapters), and the eBible English versification file (identical except 3 John 1, 15 verses there, and Revelation 12, 18 there: both are known KJV/modern-English differences, and the KJV table keeps the KJV numbers).

## Book names

English names and abbreviations, and Vietnamese names. The Vietnamese display name and the owner's short form (`sa`, `thi`, `gi`, `1co` ...) of the 1925 text come from the owner's database export (`AI/reports/bible-db-books.tsv`). Extra spellings seen in the original 1923/1925 printing (as shown on eBible: "Xuất Ai-cập", "Quan Án", "1 Lịch Sử", "Giáo Huấn", "Tình Ca", "Ai Ca", "Ê-xê-chiên", "Đa-niên", "Mi-ca", "Na-hâm", "Xô-phô-ni", "A-gai", "La-mã", "1 Phia-rơ", "Khải-thị") and a few modern ones are accepted when typing and never displayed.

Matching (`BookMatcher.match`) ignores case, diacritics (`SearchFolding`), hyphens, full stops and spacing. A leading number may be `1`, `I`, `1st` or `First`. Rules, in order:

1. An exact name or abbreviation beats a prefix.
2. Otherwise a unique prefix matches. More than one book is **reported as ambiguous with all candidates in canon order, never guessed**: `Phil` (Philippians or Philemon), `Jud` (Judges or Jude), `Jo`, `ma`. A numbered book typed without its number (`Cor`, `Samuel`) is ambiguous between the numbered books.
3. Context: `.auto` (default), `.english`, `.vietnamese`. The owner's Vietnamese abbreviations collide with English ones (`exo` is Ezra in Vietnamese and Exodus in English; `dan` is Numbers and Daniel; `es` is Isaiah and Esther; `ma`, `phi`, `phil`, `ha`, `ca`, `so`). With `.auto` such a collision is ambiguous; with `.vietnamese` or `.english` that language wins. Text containing Vietnamese diacritics is read as Vietnamese even under `.auto`. A Vietnamese short form is never silently mapped to the English book of the same letters.

## Reference parser

`ReferenceParser(language:, versification:, context:).parse(text)` returns `ParseOutcome { ranges, problems }` and never throws. Accepted: `John 3:16`, `3:16-18`, `3:16–18` (en dash; em dash and minus too), `3:16,18,20-22`, `3`, `3-4`, `3:16-4:2`, `Jn 3.16`, `1 John 1:9`, `Ps 23`, `Psalm 119:105`, single-chapter books (`Jude 5`, `Obadiah 3`, `Jude 1:5`), references separated by `;` or new lines, `John 3:16; 4:2` (the book carries over), the Vietnamese forms, and stray whitespace or punctuation at either end (`(John 3:16).`).

Decisions: a whole chapter becomes a range from verse 1 to the last verse of that chapter; a book name with no chapter is an error (it would be hundreds of slides); `John 3,5` is chapters 3 and 5 (a comma after a bare chapter lists chapters, after a verse lists verses); ranges that overlap or touch are merged, but the order the operator gave is kept. A bad reference is reported and skipped; the others in the same text are still returned. Messages say what is wrong: "John has 21 chapters", "John 3 has 36 verses", "Jude has 25 verses", "John 3:18-16 runs backwards", "“Phil” could be Philippians or Philemon". Nothing is corrected silently.

`ReferenceFormatter.format` turns ranges back into text in English or Vietnamese ("John 3:16–18", "Giăng 3:16–18", "John 3", "John 3–4", "John 3:16–4:2", "Jude 5", "John 3:16a" for part of a verse). Formatting then parsing returns the same range (tested for both languages).

## Translation file format (version 1)

One JSON file per translation. Fully documented in the header comment of `TranslationFile.swift`:

```json
{
  "format": "worshipflow.translation",
  "version": 1,
  "metadata": {
    "id": "...", "name": "...", "language": "en", "abbreviation": "...",
    "copyright": "...", "license": "...", "sourceURL": "https://...",
    "isPublicDomain": false, "versificationNote": "...", "versification": "KJV",
    "ownerApproval": {"approved": true, "date": "2026-11-20", "note": "..."}
  },
  "books": { "JHN": { "3": { "16": "verse text" } } }
}
```

Required metadata: `id`, `name`, `language` (BCP 47: `en`, `vi`), `abbreviation`. `ownerApproval` records the owner's decision to use a translation (approved, date, note); it is a record, not legal advice. A file with another `format`, no `version`, or a newer `version` is refused with a plain message. Encoding is sorted and indented, so files diff cleanly.

`TranslationLoader.load(from:)` validates and returns the translation plus a `TranslationReport` of counts: unknown books (skipped), non-numeric chapter or verse keys, duplicate verses (`"16"` and `"016"`; the first is kept), empty verses, chapters missing from books that are present, verses missing from chapters that are present, verses numbered past the table, and coverage (`complete`, `newTestamentOnly`, `oldTestamentOnly`, `partial`). A New Testament on its own is allowed and is not reported as missing chapters. `report.messages` is operator text; it is empty for a clean complete translation.

### USFM import

`USFMImporter.importBook(text)` reads one book. Kept: verse text (`\v`), with `\p`, `\q1`, `\b` and other paragraph markers joined by one space; character styles (`\w ...\w*` without its `|` attributes, `\nd`, `\add`, `\wj`, `\qs`, `\+w` ...) unwrapped; `~` as a space. Stripped with their contents: footnotes `\f ... \f*`, cross references `\x ... \x*`, figures, alternate and published verse numbers. An unclosed note ends at the next `\v`, `\c` or `\id`, with a warning. Skipped and counted by marker: headings, titles, remarks and header lines (`\s`, `\r`, `\d`, `\h`, `\toc`, `\mt`, `\rem` ...), so **Psalm titles (`\d`) are not kept**. Unknown markers are dropped and counted; the marker never shows, and the words after it are kept in case they are scripture. A verse bridge (`\v 1-2`) is stored at its first number and reported. A repeated verse keeps the first and is reported. A second `\id` stops the import with a warning. `TranslationFile.add(result)` puts the book into a file.

## Slides

`VerseSlides.build(ranges:, primary:, secondary:, options:)` returns `ScripturePresentation { title, slides, report }`. Each `ScriptureSlide` holds a `SlideContent` (primary text, optional secondary), the `reference` ("John 3:16" or "John 3:16a"), the `secondaryReference`, and the verses it covers.

- One verse per slide by default; `versesPerSlide` N puts up to N verses on a slide while `maxCharacters` (if set) allows.
- A verse longer than `maxCharacters` is split into balanced parts at sentence ends, then clause ends, then any space, never inside a word (a word longer than the limit stays whole). Parts are lettered a, b, c.
- Verse numbers: none, plain ("16 For God ..."), or superscript digits ("¹⁶ For God ...").
- The reference is a separate field, not part of the text; `SlideContent` has no reference field, so the caller places it.
- **Second translation, paired by reference.** The verses shown are those of the primary translation's table. For each, the secondary text with the same book, chapter and verse is used. If it lacks the verse that side is empty (nil) and the verse is listed in `report.missingInSecondary`; a verse the primary lacks is skipped and listed in `report.missingInPrimary`. When a verse is split, both sides are split into the same number of parts (the longer side decides); a side that runs out gets empty parts. With several verses on a slide, missing secondary verses are simply left out of the joined secondary text.
- Title: the requested reference and the abbreviations, "John 3:16–18 (KJV / VI1925)", in the primary translation's language.

## Keyword search

`ScriptureSearchIndex(translation).search(query, limit:, snippetLength:)`. Words must all appear, in any order; `"quoted words"` must appear consecutively; an unclosed quote runs to the end. Text and query are folded (case, diacritics, `đ`, punctuation), so `cau thu` finds `Câu thử`. A query word matches the start of a word in the verse (`lov` finds "loved"; `ove` does not). Results are in canon order and stop at `limit` (`truncated` says whether more existed). Snippets are built on demand around the first match. On a synthetic full-size translation (31,102 verses) in a debug build: index build about 0.4 s; a search that stops at 50 hits about 0.03 s; a search that matches nothing (full scan) about 0.14 s; every verse matching about 0.06 s. Release timings were not measured.

## Licensing position

**No translation is bundled.** `CLAUDE.md` forbids silently bundling copyrighted material, and OPEN-05 (which translations, who holds each licence) is the owner's decision. This slice ships only the rules and the file format. The owner has stated that the 1925 Vietnamese translation ("VI1925") may be used; a translation file records that in `metadata.ownerApproval`. The detailed research (what was verified from a primary source, what was inferred, where machine-readable files can be had and under what terms) is in `AI/reports/LIB-004-report.md`. Summary: the World English Bible and the Berean Standard Bible state a public-domain dedication themselves; the KJV is public domain outside the United Kingdom, where a Crown patent applies to printing; the 1925 Vietnamese text has an eBible public-domain statement for the Cadman edition but also a "©1998 Thánh Kinh Hội" notice on the edition the owner's database appears to use, so the file actually obtained carries its own terms and should be checked.

## Not done

No app wiring, no persistence, no downloading or bundling of any translation, no Hebrew/Greek or deuterocanonical books, no verse-content alignment across different versifications, no Psalm titles, no per-word styling (Jesus' words in red etc. are removed by the importer).
