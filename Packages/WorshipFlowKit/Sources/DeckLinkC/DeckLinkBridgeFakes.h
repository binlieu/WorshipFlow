// FIX-C: private header shared by the bridge and its test stand-ins (DeckLinkBridgeFakes.mm). Not part of the public module.
#pragma once

#include "DeckLinkAPI.h"

/// How the bridge creates the SDK's pixel-format converter. The real one is `CreateVideoConversionInstance`, which
/// returns null when the driver is absent; tests replace it with a stand-in.
extern IDeckLinkVideoConversion* (*DLBConversionFactory)(void);

/// A converter that does nothing (every conversion fails with E_NOTIMPL). Returns a new reference.
IDeckLinkVideoConversion* DLBNewFakeConversion(void);
