# Vendor

Third-party SDKs that are not fetched by the package manager.

## DeckLinkSDK

Blackmagic's Desktop Video SDK. Downloaded by the project owner (it needs registration and licence acceptance), then unzipped so that this path exists:

    Vendor/DeckLinkSDK/Mac/include/DeckLinkAPI.h

The contents of `Vendor/DeckLinkSDK/` are git-ignored until the licence block in the SDK files has been read and recorded in an ADR.
