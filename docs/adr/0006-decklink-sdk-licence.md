# ADR-0006: Blackmagic DeckLink SDK — what is vendored and why

Status: Accepted, 2026-11-20. This is the coordinator's reading of the licence text, not legal advice.

## Facts

- The owner downloaded Blackmagic DeckLink SDK 16.0 (API version string "16.0") into `Vendor/DeckLinkSDK/`, accepting Blackmagic's End User License Agreement for the SDK.
- The EULA's clause 0.1 says clauses 1, 4.3, 4.4, 5, 7 and 8 do **not** apply to the files in `/Mac/Include`, `/Win/Include` and `/Linux/Include`.
- Each file in `Mac/include` carries its own notice granting permission "to use, reproduce, display, distribute, sub-license, execute, and transmit the Software, and to prepare derivative works", provided the copyright notice and the whole statement stay in all source copies. Copies "solely in the form of machine-executable object code" do not need the notice.
- The rest of the SDK, including the sample code, is under the full EULA: sample source may be used "internally" only, and redistribution of the SDK must be in full under the same terms.
- EULA clause 6.2 permits the wording "WORSHIPFLOW compatible with Blackmagic Design DeckLink" and "WORSHIPFLOW for Blackmagic Design DeckLink".

## Decisions

| # | Decision |
|---|---|
| 1 | The current-version files from `Mac/include` that the bridge needs are copied, unmodified, into `Packages/WorshipFlowKit/Sources/DeckLinkC/sdk/` and committed, notices intact. Legacy `_vNN` files are not copied. |
| 2 | Nothing else from the SDK enters the repository: no samples, no documentation, no binaries. `Vendor/DeckLinkSDK/` stays git-ignored. |
| 3 | Agents may read the SDK samples and manual to learn the API. They must not copy sample code into the project; the bridge is written from the headers and the documented call sequence. |
| 4 | A built app contains only object code from those headers and the dispatch file, so it can be given to a tester. It does not contain the Desktop Video driver: each Mac installs that from Blackmagic. |
| 5 | Product wording about compatibility uses only the forms in clause 6.2, and only after hardware verification. |
| 6 | If the repository is ever made public or the app is sold, re-read the EULA and the notice first. |
