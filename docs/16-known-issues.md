# Known issues and open risks

| ID | Issue | State |
|---|---|---|
| KI-001 | No DeckLink, enclosure or ATEM is owned. Every `HW` and `KEY` slice can reach "Simulated" at most. | Open. Needs purchase by the owner. |
| KI-002 | Desktop Video support for macOS 27 is unconfirmed (spec UNV-01). | Open. |
| KI-003 | The development Mac has two displays. Stage output is checked in an output window. | Accepted. |
| KI-004 | Both displays run at 100 Hz. Timing tests must use a 60 Hz mode or the result does not count toward NFR-01. | Open until Phase 0 measurement. |
| KI-005 | The repository sits on a case-sensitive APFS volume with ownership disabled (spec UNV-07). | Watch. |
| KI-006 | Spec conflicts with `CLAUDE.md` are listed in `docs/adr/0003-spec-overrides.md`. | Recorded. |
