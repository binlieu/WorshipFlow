// HW-003: the DeckLink bridge. Objective-C++ around the vendored SDK 16.0 headers in sdk/ (ADR-0006).
//
// Written from the headers and the documented call sequences (manual sections 2.4.2 output, 2.4.6 format detection,
// 2.4.8 keying, 2.4.11 profiles, 2.4.14 conversion). No sample code is used.
//
// Status: Implemented, Not Verified. It has run only with the driver absent.
//
// Rules this file follows:
//  - Every COM pointer lives in a ComPtr, so it is released exactly once.
//  - Callbacks from the SDK touch only shared_ptr state objects, never ObjC objects that could be mid-dealloc, and no
//    handler is called while a bridge lock is held.
//  - No C++ exception leaves an Objective-C method or an SDK callback.
#import "DeckLinkBridge.h"

#import <CoreFoundation/CoreFoundation.h>

#include "DeckLinkAPI.h"
#include "DeckLinkAPIVersion.h"

#include <atomic>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <vector>

#include <dispatch/dispatch.h>

NSErrorDomain const DLBErrorDomain = @"com.worshipflow.decklink";
NSErrorUserInfoKey const DLBErrorHRESULTKey = @"DLBHRESULT";

// MARK: - Small helpers

namespace {

/// Owns one reference to a COM object. Copying adds a reference; destruction releases it.
template <class T>
class ComPtr {
public:
    ComPtr() = default;
    ComPtr(const ComPtr& other) : ptr_(other.ptr_) { if (ptr_) ptr_->AddRef(); }
    ComPtr(ComPtr&& other) noexcept : ptr_(other.ptr_) { other.ptr_ = nullptr; }
    ComPtr& operator=(const ComPtr& other) {
        if (this != &other) {
            if (other.ptr_) other.ptr_->AddRef();
            reset();
            ptr_ = other.ptr_;
        }
        return *this;
    }
    ComPtr& operator=(ComPtr&& other) noexcept {
        if (this != &other) { reset(); ptr_ = other.ptr_; other.ptr_ = nullptr; }
        return *this;
    }
    ~ComPtr() { reset(); }

    /// Takes over a reference the caller already owns (what the SDK's out parameters hand back).
    static ComPtr adopt(T* raw) { ComPtr p; p.ptr_ = raw; return p; }
    /// Takes a new reference to an object the caller does not own.
    static ComPtr retain(T* raw) { ComPtr p; p.ptr_ = raw; if (raw) raw->AddRef(); return p; }

    T* get() const { return ptr_; }
    T* operator->() const { return ptr_; }
    explicit operator bool() const { return ptr_ != nullptr; }
    /// Releases what is held and returns the address for an SDK out parameter.
    T** put() { reset(); return &ptr_; }
    void reset() { if (ptr_) { T* old = ptr_; ptr_ = nullptr; old->Release(); } }

    template <class U>
    ComPtr<U> as(REFIID iid) const {
        U* out = nullptr;
        if (ptr_ && ptr_->QueryInterface(iid, reinterpret_cast<LPVOID*>(&out)) == S_OK) return ComPtr<U>::adopt(out);
        return ComPtr<U>();
    }

private:
    T* ptr_ = nullptr;
};

bool SameIID(REFIID a, REFIID b) { return std::memcmp(&a, &b, sizeof(CFUUIDBytes)) == 0; }

bool IsIUnknown(REFIID iid) {
    CFUUIDRef uuid = IUnknownUUID;
    CFUUIDBytes bytes = CFUUIDGetUUIDBytes(uuid);
    return SameIID(iid, bytes);
}

NSString* TakeCFString(CFStringRef s) {
    if (s == nullptr) return @"";
    return (__bridge_transfer NSString*)s;
}

NSString* FourCC(uint32_t v) {
    char c[5] = {char(v >> 24), char(v >> 16), char(v >> 8), char(v), 0};
    for (int i = 0; i < 4; i++) {
        if (c[i] < 0x20 || c[i] > 0x7e) return [NSString stringWithFormat:@"0x%08X", v];
    }
    return [NSString stringWithUTF8String:c];
}

DLBErrorCode CodeForHRESULT(HRESULT hr) {
    switch (hr) {
        case E_ACCESSDENIED: return DLBErrorBusy;
        case E_OUTOFMEMORY: return DLBErrorOutOfMemory;
        case E_NOTIMPL: return DLBErrorNotSupported;
        case E_INVALIDARG: return DLBErrorBadArgument;
        default: return DLBErrorSDKFailure;
    }
}

NSError* MakeError(DLBErrorCode code, NSString* message, bool hasHRESULT = false, HRESULT hr = S_OK) {
    NSMutableDictionary* info = [NSMutableDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    if (hasHRESULT) info[DLBErrorHRESULTKey] = @((int32_t)hr);
    return [NSError errorWithDomain:DLBErrorDomain code:code userInfo:info];
}

BOOL Fail(NSError** error, DLBErrorCode code, NSString* message) {
    if (error) *error = MakeError(code, message);
    return NO;
}

BOOL FailHR(NSError** error, HRESULT hr, NSString* what) {
    if (error) {
        *error = MakeError(CodeForHRESULT(hr), [NSString stringWithFormat:@"%@ (SDK result 0x%08X)", what, (uint32_t)hr], true, hr);
    }
    return NO;
}

NSString* DriverMissingMessage() {
    return @"Blackmagic Desktop Video is not installed on this Mac.";
}

bool AttrFlag(IDeckLinkProfileAttributes* a, BMDDeckLinkAttributeID id, bool* out) {
    if (!a) return false;
    bool v = false;
    if (a->GetFlag(id, &v) != S_OK) return false;
    *out = v;
    return true;
}

bool AttrInt(IDeckLinkProfileAttributes* a, BMDDeckLinkAttributeID id, int64_t* out) {
    if (!a) return false;
    int64_t v = 0;
    if (a->GetInt(id, &v) != S_OK) return false;
    *out = v;
    return true;
}

NSString* FourCCOrNone(bool have, uint32_t v) { return have ? FourCC(v) : @"unknown"; }

/// 64K table: premultiplied colour (low byte) and alpha (high byte) to straight colour. Same rounding as the
/// fill/key splitter in SDIEngine, so keyed output matches what that module produces.
const uint8_t* UnpremultiplyTable() {
    static const std::vector<uint8_t> table = [] {
        std::vector<uint8_t> t(256 * 256, 0);
        for (int a = 1; a < 256; a++) {
            for (int c = 0; c < 256; c++) {
                int v = a == 255 ? c : (c * 255 + a / 2) / a;
                t[(a << 8) | c] = (uint8_t)(v > 255 ? 255 : v);
            }
        }
        return t;
    }();
    return table.data();
}

}  // namespace

// MARK: - Packing

BOOL DLBPackBGRA(const uint8_t* source, size_t sourceRowBytes, size_t width, size_t height,
                 uint8_t* destination, size_t destinationRowBytes, DLBAlphaMode alphaMode) {
    if (!source || !destination || width == 0 || height == 0) return NO;
    const size_t rowLength = width * 4;
    if (sourceRowBytes < rowLength || destinationRowBytes < rowLength) return NO;
    if (alphaMode == DLBAlphaModeStraight) {
        const uint8_t* table = UnpremultiplyTable();
        for (size_t y = 0; y < height; y++) {
            const uint8_t* s = source + y * sourceRowBytes;
            uint8_t* d = destination + y * destinationRowBytes;
            for (size_t x = 0; x < width; x++) {
                const uint8_t a = s[3];
                const size_t row = (size_t)a << 8;
                d[0] = table[row | s[0]];
                d[1] = table[row | s[1]];
                d[2] = table[row | s[2]];
                d[3] = a;
                s += 4;
                d += 4;
            }
        }
    } else {
        for (size_t y = 0; y < height; y++) {
            std::memcpy(destination + y * destinationRowBytes, source + y * sourceRowBytes, rowLength);
        }
    }
    return YES;
}

// MARK: - Driver info

@interface DLBDriverInfo ()
@property (nonatomic, readwrite) BOOL present;
@property (nonatomic, readwrite, copy, nullable) NSString* apiVersionString;
@property (nonatomic, readwrite) int64_t apiVersionRaw;
@end

@implementation DLBDriverInfo

+ (NSString*)compiledAPIVersionString { return [NSString stringWithUTF8String:BLACKMAGIC_DECKLINK_API_VERSION_STRING]; }

+ (DLBDriverInfo*)current {
    DLBDriverInfo* info = [[DLBDriverInfo alloc] initPrivate];
    try {
        ComPtr<IDeckLinkAPIInformation> api = ComPtr<IDeckLinkAPIInformation>::adopt(CreateDeckLinkAPIInformationInstance());
        if (!api) return info;
        info.present = YES;
        int64_t raw = 0;
        if (api->GetInt(BMDDeckLinkAPIVersion, &raw) == S_OK) {
            info.apiVersionRaw = raw;
            info.apiVersionString = [NSString stringWithFormat:@"%lld.%lld", (raw >> 24) & 0xff, (raw >> 16) & 0xff];
        }
        CFStringRef s = nullptr;
        if (api->GetString(BMDDeckLinkAPIVersion, &s) == S_OK && s != nullptr) {
            NSString* str = TakeCFString(s);
            if (str.length > 0) info.apiVersionString = str;
        }
    } catch (...) {
    }
    return info;
}

- (instancetype)initPrivate { return [super init]; }

@end

// MARK: - Profile and device info

@interface DLBProfileInfo ()
@property (nonatomic, readwrite) uint32_t profileID;
@property (nonatomic, readwrite) BOOL isActive;
@property (nonatomic, readwrite) BOOL supportsExternalKeying;
@property (nonatomic, readwrite) BOOL supportsInternalKeying;
@property (nonatomic, readwrite) BOOL supportsPlayback;
@property (nonatomic, readwrite) BOOL supportsCapture;
@property (nonatomic, readwrite) uint32_t duplexMode;
@property (nonatomic, readwrite) int64_t numberOfSubDevices;
@property (nonatomic, readonly, copy) NSDictionary<NSString*, id>* snapshot;
- (instancetype)initPrivate;
@end

@implementation DLBProfileInfo
- (instancetype)initPrivate { return [super init]; }
- (NSString*)profileIDString { return FourCC(_profileID); }
- (NSString*)duplexModeString { return FourCCOrNone(_duplexMode != 0, _duplexMode); }
- (NSDictionary<NSString*, id>*)snapshot {
    return @{
        @"profileID": self.profileIDString,
        @"isActive": @(_isActive),
        @"supportsExternalKeying": @(_supportsExternalKeying),
        @"supportsInternalKeying": @(_supportsInternalKeying),
        @"supportsPlayback": @(_supportsPlayback),
        @"supportsCapture": @(_supportsCapture),
        @"duplexMode": self.duplexModeString,
        @"numberOfSubDevices": @(_numberOfSubDevices),
    };
}
@end

@interface DLBDeviceInfo ()
@property (nonatomic, readwrite, copy) NSString* modelName;
@property (nonatomic, readwrite, copy) NSString* displayName;
@property (nonatomic, readwrite) BOOL hasPersistentID;
@property (nonatomic, readwrite) int64_t persistentID;
@property (nonatomic, readwrite) BOOL hasDeviceGroupID;
@property (nonatomic, readwrite) int64_t deviceGroupID;
@property (nonatomic, readwrite) BOOL hasTopologicalID;
@property (nonatomic, readwrite) int64_t topologicalID;
@property (nonatomic, readwrite) int64_t subDeviceIndex;
@property (nonatomic, readwrite) int64_t numberOfSubDevices;
@property (nonatomic, readwrite) BOOL supportsPlayback;
@property (nonatomic, readwrite) BOOL supportsCapture;
@property (nonatomic, readwrite) BOOL supportsInternalKeying;
@property (nonatomic, readwrite) BOOL supportsExternalKeying;
@property (nonatomic, readwrite) BOOL supportsInputFormatDetection;
@property (nonatomic, readwrite) uint32_t videoOutputConnections;
@property (nonatomic, readwrite) uint32_t videoInputConnections;
@property (nonatomic, readwrite) uint32_t duplexMode;
@property (nonatomic, readwrite) BOOL hasSingleProfile;
@property (nonatomic, readwrite) BOOL hasActiveProfile;
@property (nonatomic, readwrite) uint32_t activeProfileID;
@property (nonatomic, readwrite, copy) NSArray<DLBProfileInfo*>* profiles;
@property (nonatomic, readwrite) int64_t minimumPrerollFrames;
@property (nonatomic, readwrite) BOOL hasOutputInterface;
@property (nonatomic, readwrite) BOOL hasInputInterface;
@property (nonatomic, readwrite) BOOL hasKeyerInterface;
@property (nonatomic, readwrite) uint32_t deviceInterface;
@property (nonatomic, readwrite, copy) NSDictionary<NSString*, id>* snapshot;
- (instancetype)initPrivate;
@end

@implementation DLBDeviceInfo
- (instancetype)initPrivate { return [super init]; }
- (NSString*)duplexModeString { return FourCCOrNone(_duplexMode != 0, _duplexMode); }
- (NSString*)activeProfileIDString { return FourCCOrNone(_hasActiveProfile, _activeProfileID); }
- (NSString*)deviceInterfaceString { return FourCCOrNone(_deviceInterface != 0, _deviceInterface); }
@end

namespace {

/// Reads the attributes of a profile or of the active profile into `profile`.
DLBProfileInfo* ReadProfile(IDeckLinkProfile* p) {
    DLBProfileInfo* out = [[DLBProfileInfo alloc] initPrivate];
    bool active = false;
    if (p->IsActive(&active) == S_OK) out.isActive = active;
    ComPtr<IDeckLinkProfileAttributes> attrs = ComPtr<IDeckLinkProfile>::retain(p).as<IDeckLinkProfileAttributes>(IID_IDeckLinkProfileAttributes);
    int64_t i = 0;
    bool f = false;
    if (AttrInt(attrs.get(), BMDDeckLinkProfileID, &i)) out.profileID = (uint32_t)i;
    if (AttrFlag(attrs.get(), BMDDeckLinkSupportsExternalKeying, &f)) out.supportsExternalKeying = f;
    f = false;
    if (AttrFlag(attrs.get(), BMDDeckLinkSupportsInternalKeying, &f)) out.supportsInternalKeying = f;
    out.numberOfSubDevices = AttrInt(attrs.get(), BMDDeckLinkNumberOfSubDevices, &i) ? i : -1;
    if (AttrInt(attrs.get(), BMDDeckLinkDuplex, &i)) out.duplexMode = (uint32_t)i;
    if (AttrInt(attrs.get(), BMDDeckLinkVideoIOSupport, &i)) {
        out.supportsPlayback = (i & bmdDeviceSupportsPlayback) != 0;
        out.supportsCapture = (i & bmdDeviceSupportsCapture) != 0;
    }
    return out;
}

DLBDeviceInfo* BuildInfo(IDeckLink* dl) {
    DLBDeviceInfo* info = [[DLBDeviceInfo alloc] initPrivate];
    ComPtr<IDeckLink> device = ComPtr<IDeckLink>::retain(dl);

    CFStringRef s = nullptr;
    info.modelName = (device->GetModelName(&s) == S_OK) ? TakeCFString(s) : @"DeckLink";
    s = nullptr;
    info.displayName = (device->GetDisplayName(&s) == S_OK) ? TakeCFString(s) : info.modelName;

    ComPtr<IDeckLinkProfileAttributes> attrs = device.as<IDeckLinkProfileAttributes>(IID_IDeckLinkProfileAttributes);
    int64_t i = 0;
    bool f = false;
    if (AttrInt(attrs.get(), BMDDeckLinkPersistentID, &i)) { info.hasPersistentID = YES; info.persistentID = i; }
    if (AttrInt(attrs.get(), BMDDeckLinkDeviceGroupID, &i)) { info.hasDeviceGroupID = YES; info.deviceGroupID = i; }
    if (AttrInt(attrs.get(), BMDDeckLinkTopologicalID, &i)) { info.hasTopologicalID = YES; info.topologicalID = i; }
    info.subDeviceIndex = AttrInt(attrs.get(), BMDDeckLinkSubDeviceIndex, &i) ? i : -1;
    info.numberOfSubDevices = AttrInt(attrs.get(), BMDDeckLinkNumberOfSubDevices, &i) ? i : -1;
    info.minimumPrerollFrames = AttrInt(attrs.get(), BMDDeckLinkMinimumPrerollFrames, &i) ? i : -1;
    info.supportsInternalKeying = AttrFlag(attrs.get(), BMDDeckLinkSupportsInternalKeying, &f) && f;
    f = false;
    info.supportsExternalKeying = AttrFlag(attrs.get(), BMDDeckLinkSupportsExternalKeying, &f) && f;
    f = false;
    info.supportsInputFormatDetection = AttrFlag(attrs.get(), BMDDeckLinkSupportsInputFormatDetection, &f) && f;
    if (AttrInt(attrs.get(), BMDDeckLinkVideoOutputConnections, &i)) info.videoOutputConnections = (uint32_t)i;
    if (AttrInt(attrs.get(), BMDDeckLinkVideoInputConnections, &i)) info.videoInputConnections = (uint32_t)i;
    if (AttrInt(attrs.get(), BMDDeckLinkDuplex, &i)) info.duplexMode = (uint32_t)i;
    if (AttrInt(attrs.get(), BMDDeckLinkDeviceInterface, &i)) info.deviceInterface = (uint32_t)i;
    if (AttrInt(attrs.get(), BMDDeckLinkProfileID, &i)) { info.hasActiveProfile = YES; info.activeProfileID = (uint32_t)i; }
    if (AttrInt(attrs.get(), BMDDeckLinkVideoIOSupport, &i)) {
        info.supportsPlayback = (i & bmdDeviceSupportsPlayback) != 0;
        info.supportsCapture = (i & bmdDeviceSupportsCapture) != 0;
    }

    info.hasOutputInterface = (bool)device.as<IDeckLinkOutput>(IID_IDeckLinkOutput);
    info.hasInputInterface = (bool)device.as<IDeckLinkInput>(IID_IDeckLinkInput);
    info.hasKeyerInterface = (bool)device.as<IDeckLinkKeyer>(IID_IDeckLinkKeyer);

    // Profiles. No IDeckLinkProfileManager means the device has exactly one profile.
    NSMutableArray<DLBProfileInfo*>* profiles = [NSMutableArray array];
    ComPtr<IDeckLinkProfileManager> manager = device.as<IDeckLinkProfileManager>(IID_IDeckLinkProfileManager);
    info.hasSingleProfile = !manager;
    if (manager) {
        ComPtr<IDeckLinkProfileIterator> it;
        if (manager->GetProfiles(it.put()) == S_OK && it) {
            for (;;) {
                ComPtr<IDeckLinkProfile> p;
                if (it->Next(p.put()) != S_OK || !p) break;
                [profiles addObject:ReadProfile(p.get())];
            }
        }
    }
    info.profiles = profiles;

    NSMutableArray* profileDicts = [NSMutableArray array];
    for (DLBProfileInfo* p in profiles) [profileDicts addObject:p.snapshot];

    info.snapshot = @{
        @"modelName": info.modelName,
        @"displayName": info.displayName,
        @"persistentID": info.hasPersistentID ? (id)@(info.persistentID) : (id)[NSNull null],
        @"deviceGroupID": info.hasDeviceGroupID ? (id)@(info.deviceGroupID) : (id)[NSNull null],
        @"topologicalID": info.hasTopologicalID ? (id)@(info.topologicalID) : (id)[NSNull null],
        @"subDeviceIndex": @(info.subDeviceIndex),
        @"numberOfSubDevices": @(info.numberOfSubDevices),
        @"supportsPlayback": @(info.supportsPlayback),
        @"supportsCapture": @(info.supportsCapture),
        @"supportsInternalKeying": @(info.supportsInternalKeying),
        @"supportsExternalKeying": @(info.supportsExternalKeying),
        @"supportsInputFormatDetection": @(info.supportsInputFormatDetection),
        @"videoOutputConnections": @(info.videoOutputConnections),
        @"videoInputConnections": @(info.videoInputConnections),
        @"duplexMode": info.duplexModeString,
        @"deviceInterface": info.deviceInterfaceString,
        @"minimumPrerollFrames": @(info.minimumPrerollFrames),
        @"hasSingleProfile": @(info.hasSingleProfile),
        @"activeProfileID": info.activeProfileIDString,
        @"profiles": profileDicts,
        @"hasOutputInterface": @(info.hasOutputInterface),
        @"hasInputInterface": @(info.hasInputInterface),
        @"hasKeyerInterface": @(info.hasKeyerInterface),
    };
    return info;
}

// MARK: - Output state

struct PoolEntry {
    ComPtr<IDeckLinkMutableVideoFrame> frame;
    ComPtr<IDeckLinkVideoBuffer> buffer;
    int64_t frameIndex = -1;
    uint64_t sequence = 0;
    bool inFlight = false;
};

/// Everything the SDK callback thread and the Objective-C object share. Held by shared_ptr from both sides.
struct OutputState {
    std::mutex mutex;
    ComPtr<IDeckLinkOutput> output;
    ComPtr<IDeckLinkKeyer> keyer;
    ComPtr<IDeckLinkVideoOutputCallback> callback;
    bool enabled = false;
    bool playing = false;
    bool closed = false;
    bool keyerOn = false;
    bool removed = false;
    uint32_t mode = 0;
    int32_t width = 0;
    int32_t height = 0;
    int32_t rowBytes = 0;
    int64_t frameDuration = 0;
    int64_t timeScale = 0;
    uint8_t keyerLevel = 255;
    std::vector<PoolEntry> pool;
    uint64_t nextSequence = 1;
    uint64_t scheduled = 0, completed = 0, late = 0, dropped = 0, flushed = 0, unknown = 0;
    DLBFrameCompletionHandler completionHandler;
    DLBFailureHandler failureHandler;
};

constexpr size_t kMaxPoolFrames = 16;

DLBCompletionResult MapResult(BMDOutputFrameCompletionResult r) {
    switch (r) {
        case bmdOutputFrameCompleted: return DLBCompletionResultCompleted;
        case bmdOutputFrameDisplayedLate: return DLBCompletionResultDisplayedLate;
        case bmdOutputFrameDropped: return DLBCompletionResultDropped;
        case bmdOutputFrameFlushed: return DLBCompletionResultFlushed;
        default: return DLBCompletionResultUnknown;
    }
}

class OutputCallback final : public IDeckLinkVideoOutputCallback {
public:
    explicit OutputCallback(std::shared_ptr<OutputState> state) : state_(std::move(state)) {}

    HRESULT QueryInterface(REFIID iid, LPVOID* ppv) override {
        if (!ppv) return E_POINTER;
        if (IsIUnknown(iid) || SameIID(iid, IID_IDeckLinkVideoOutputCallback)) {
            *ppv = static_cast<IDeckLinkVideoOutputCallback*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG AddRef() override { return ++refs_; }
    ULONG Release() override {
        ULONG n = --refs_;
        if (n == 0) delete this;
        return n;
    }

    HRESULT ScheduledFrameCompleted(IDeckLinkVideoFrame* completedFrame, BMDOutputFrameCompletionResult result) override {
        try {
            int64_t index = -1;
            DLBFrameCompletionHandler handler;
            const DLBCompletionResult mapped = MapResult(result);
            {
                std::lock_guard<std::mutex> lock(state_->mutex);
                PoolEntry* hit = nullptr;
                for (PoolEntry& e : state_->pool) {
                    if (e.inFlight && static_cast<IDeckLinkVideoFrame*>(e.frame.get()) == completedFrame) { hit = &e; break; }
                }
                if (!hit) {
                    // The SDK handed back an object we do not recognise. Frames complete in scheduling order, so the
                    // oldest one in flight is the best answer.
                    for (PoolEntry& e : state_->pool) {
                        if (e.inFlight && (!hit || e.sequence < hit->sequence)) hit = &e;
                    }
                }
                if (hit) { index = hit->frameIndex; hit->inFlight = false; }
                switch (mapped) {
                    case DLBCompletionResultCompleted: state_->completed++; break;
                    case DLBCompletionResultDisplayedLate: state_->late++; break;
                    case DLBCompletionResultDropped: state_->dropped++; break;
                    case DLBCompletionResultFlushed: state_->flushed++; break;
                    default: state_->unknown++; break;
                }
                handler = state_->completionHandler;
            }
            if (handler) handler(index, mapped);
        } catch (...) {
        }
        return S_OK;
    }

    HRESULT ScheduledPlaybackHasStopped() override {
        try {
            std::lock_guard<std::mutex> lock(state_->mutex);
            state_->playing = false;
        } catch (...) {
        }
        return S_OK;
    }

private:
    ~OutputCallback() override = default;
    std::atomic<ULONG> refs_{1};
    std::shared_ptr<OutputState> state_;
};

// MARK: - Input state

struct InputState {
    std::mutex mutex;
    ComPtr<IDeckLinkInput> input;
    ComPtr<IDeckLinkInputCallback> callback;
    ComPtr<IDeckLinkVideoConversion> conversion;
    bool running = false;
    bool closed = false;
    bool detect = false;
    int signal = -1;  // -1 unknown, 0 no signal, 1 signal
    BMDPixelFormat pixelFormat = bmdFormat8BitYUV;
    BMDVideoInputFlags flags = bmdVideoInputFlagDefault;
    uint32_t mode = 0;
    uint64_t frames = 0, noSignalFrames = 0, conversions = 0, conversionFailures = 0, formatChanges = 0;
    DLBInputFrameHandler frameHandler;
    DLBSignalHandler signalHandler;
    DLBInputFormatHandler formatHandler;
    DLBFailureHandler failureHandler;
    dispatch_queue_t queue = nullptr;
};

constexpr BMDTimeScale kTimestampScale = 1000000000;  // nanoseconds

/// Reads `frame`'s bytes (through IDeckLinkVideoBuffer, as SDK 16.0 requires) and calls `body` with them.
template <class Body>
bool WithFrameBytes(IDeckLinkVideoFrame* frame, Body&& body) {
    ComPtr<IDeckLinkVideoBuffer> buffer = ComPtr<IDeckLinkVideoFrame>::retain(frame).as<IDeckLinkVideoBuffer>(IID_IDeckLinkVideoBuffer);
    if (!buffer) return false;
    if (buffer->StartAccess(bmdBufferAccessRead) != S_OK) return false;
    void* bytes = nullptr;
    const bool ok = buffer->GetBytes(&bytes) == S_OK && bytes != nullptr;
    if (ok) body(static_cast<const uint8_t*>(bytes));
    buffer->EndAccess(bmdBufferAccessRead);
    return ok;
}

void RunFormatChange(const std::shared_ptr<InputState>& st, BMDDisplayMode newMode, BMDPixelFormat newFormat) {
    ComPtr<IDeckLinkInput> input;
    BMDVideoInputFlags flags;
    {
        std::lock_guard<std::mutex> lock(st->mutex);
        if (!st->running || st->closed || !st->input) return;
        input = st->input;
        flags = st->flags;
    }
    // The SDK may wait for in-flight frame callbacks inside these calls, and those take the state lock, so the lock must
    // not be held here. Documented restart sequence for a detected change: pause, re-enable, flush, start.
    input->PauseStreams();
    const bool enabled = input->EnableVideoInput(newMode, newFormat, flags) == S_OK;
    input->FlushStreams();
    input->StartStreams();
    bool stoppedMeanwhile;
    {
        std::lock_guard<std::mutex> lock(st->mutex);
        stoppedMeanwhile = !st->running || st->closed;
        if (enabled && !stoppedMeanwhile) {
            st->mode = newMode;
            st->pixelFormat = newFormat;
        }
    }
    if (stoppedMeanwhile) {
        // stop() ran while the restart was under way; undo what the restart switched back on.
        input->StopStreams();
        input->DisableVideoInput();
    }
}

class InputCallback final : public IDeckLinkInputCallback {
public:
    explicit InputCallback(std::shared_ptr<InputState> state) : state_(std::move(state)) {}

    HRESULT QueryInterface(REFIID iid, LPVOID* ppv) override {
        if (!ppv) return E_POINTER;
        if (IsIUnknown(iid) || SameIID(iid, IID_IDeckLinkInputCallback)) {
            *ppv = static_cast<IDeckLinkInputCallback*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG AddRef() override { return ++refs_; }
    ULONG Release() override {
        ULONG n = --refs_;
        if (n == 0) delete this;
        return n;
    }

    HRESULT VideoInputFormatChanged(BMDVideoInputFormatChangedEvents events, IDeckLinkDisplayMode* newMode,
                                    BMDDetectedVideoInputFormatFlags flags) override {
        try {
            if (!newMode) return S_OK;
            const BMDDisplayMode mode = newMode->GetDisplayMode();
            const int32_t width = (int32_t)newMode->GetWidth();
            const int32_t height = (int32_t)newMode->GetHeight();
            BMDTimeValue duration = 0;
            BMDTimeScale scale = 0;
            newMode->GetFrameRate(&duration, &scale);
            const BMDFieldDominance field = newMode->GetFieldDominance();
            const bool interlaced = field == bmdLowerFieldFirst || field == bmdUpperFieldFirst;
            const BMDPixelFormat format = (flags & bmdDetectedVideoInputRGB444) ? bmdFormat8BitBGRA : bmdFormat8BitYUV;
            (void)events;

            DLBInputFormatHandler handler;
            dispatch_queue_t queue = nullptr;
            {
                std::lock_guard<std::mutex> lock(state_->mutex);
                if (!state_->running || state_->closed) return S_OK;
                state_->formatChanges++;
                handler = state_->formatHandler;
                queue = state_->queue;
            }
            // The restart is done off the SDK's callback thread; frames that arrive meanwhile are dropped by the SDK.
            std::shared_ptr<InputState> st = state_;
            dispatch_async(queue, ^{
                try {
                    RunFormatChange(st, mode, format);
                } catch (...) {
                }
                if (handler) handler(mode, width, height, duration, scale, interlaced);
            });
        } catch (...) {
        }
        return S_OK;
    }

    HRESULT VideoInputFrameArrived(IDeckLinkVideoInputFrame* frame, IDeckLinkAudioInputPacket* /*audio*/) override {
        try {
            handleFrame(frame);
        } catch (...) {
        }
        return S_OK;
    }

private:
    ~InputCallback() override = default;

    void handleFrame(IDeckLinkVideoInputFrame* frame) {
        if (!frame) return;
        const bool noSource = (frame->GetFlags() & bmdFrameHasNoInputSource) != 0;

        DLBInputFrameHandler frameHandler;
        DLBSignalHandler signalHandler;
        ComPtr<IDeckLinkVideoConversion> conversion;
        bool signalChanged = false;
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            if (!state_->running || state_->closed) return;
            const int now = noSource ? 0 : 1;
            if (state_->signal != now) { state_->signal = now; signalChanged = true; }
            if (noSource) state_->noSignalFrames++; else state_->frames++;
            frameHandler = state_->frameHandler;
            signalHandler = state_->signalHandler;
            conversion = state_->conversion;
        }
        if (signalChanged && signalHandler) signalHandler(!noSource);
        if (noSource || !frameHandler) return;

        int64_t timestamp = -1;
        BMDTimeValue t = 0, d = 0;
        if (frame->GetHardwareReferenceTimestamp(kTimestampScale, &t, &d) == S_OK) timestamp = t;

        const int32_t width = (int32_t)frame->GetWidth();
        const int32_t height = (int32_t)frame->GetHeight();

        if (frame->GetPixelFormat() == bmdFormat8BitBGRA) {
            const size_t rowBytes = (size_t)frame->GetRowBytes();
            WithFrameBytes(frame, [&](const uint8_t* bytes) { frameHandler(bytes, rowBytes * (size_t)height, width, height, rowBytes, timestamp); });
            return;
        }
        if (!conversion) return;
        ComPtr<IDeckLinkVideoFrame> converted;
        const HRESULT hr = conversion->ConvertNewFrame(frame, bmdFormat8BitBGRA, bmdColorspaceRec709, nullptr, converted.put());
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            if (hr == S_OK && converted) state_->conversions++; else state_->conversionFailures++;
        }
        if (hr != S_OK || !converted) return;
        const size_t rowBytes = (size_t)converted->GetRowBytes();
        WithFrameBytes(converted.get(), [&](const uint8_t* bytes) { frameHandler(bytes, rowBytes * (size_t)height, width, height, rowBytes, timestamp); });
    }

    std::atomic<ULONG> refs_{1};
    std::shared_ptr<InputState> state_;
};

}  // namespace

// MARK: - Forward declarations of the private surface

@interface DLBOutput ()
- (instancetype)initWithOutput:(ComPtr<IDeckLinkOutput>)output keyer:(ComPtr<IDeckLinkKeyer>)keyer;
- (void)deviceWasRemoved;
@end

@interface DLBInput ()
- (instancetype)initWithInput:(ComPtr<IDeckLinkInput>)input supportsDetection:(BOOL)supportsDetection;
- (void)deviceWasRemoved;
@end

@interface DLBDevice ()
- (instancetype)initWithDeckLink:(IDeckLink*)deckLink;
- (void)markRemoved;
- (IDeckLink*)rawDeckLink;
@end

// MARK: - DLBOutput

@implementation DLBOutput {
    std::shared_ptr<OutputState> _state;
    ComPtr<IDeckLinkOutput> _output;
}

- (instancetype)initWithOutput:(ComPtr<IDeckLinkOutput>)output keyer:(ComPtr<IDeckLinkKeyer>)keyer {
    self = [super init];
    if (self) {
        _state = std::make_shared<OutputState>();
        _state->output = output;
        _state->keyer = keyer;
        _output = output;
    }
    return self;
}

- (void)dealloc { [self close]; }

- (DLBFrameCompletionHandler)completionHandler {
    std::lock_guard<std::mutex> lock(_state->mutex);
    return _state->completionHandler;
}
- (void)setCompletionHandler:(DLBFrameCompletionHandler)handler {
    std::lock_guard<std::mutex> lock(_state->mutex);
    _state->completionHandler = [handler copy];
}
- (DLBFailureHandler)failureHandler {
    std::lock_guard<std::mutex> lock(_state->mutex);
    return _state->failureHandler;
}
- (void)setFailureHandler:(DLBFailureHandler)handler {
    std::lock_guard<std::mutex> lock(_state->mutex);
    _state->failureHandler = [handler copy];
}

- (BOOL)isEnabled { std::lock_guard<std::mutex> lock(_state->mutex); return _state->enabled; }
- (BOOL)isPlaying { std::lock_guard<std::mutex> lock(_state->mutex); return _state->playing; }
- (BOOL)isClosed { std::lock_guard<std::mutex> lock(_state->mutex); return _state->closed; }

- (uint32_t)bufferedFrameCount {
    ComPtr<IDeckLinkOutput> out;
    {
        std::lock_guard<std::mutex> lock(_state->mutex);
        if (!_state->enabled || _state->closed) return 0;
        out = _state->output;
    }
    uint32_t n = 0;
    if (out->GetBufferedVideoFrameCount(&n) != S_OK) return 0;
    return n;
}

- (BOOL)supportsDisplayMode:(uint32_t)displayMode keying:(BOOL)keying actualMode:(uint32_t*)actualMode {
    ComPtr<IDeckLinkOutput> out;
    {
        std::lock_guard<std::mutex> lock(_state->mutex);
        if (_state->closed || !_state->output) return NO;
        out = _state->output;
    }
    try {
        BMDDisplayMode actual = bmdModeUnknown;
        bool supported = false;
        const HRESULT hr = out->DoesSupportVideoMode(bmdVideoConnectionUnspecified, (BMDDisplayMode)displayMode, bmdFormat8BitBGRA,
                                                     bmdNoVideoOutputConversion,
                                                     keying ? bmdSupportedVideoModeKeying : bmdSupportedVideoModeDefault,
                                                     &actual, &supported);
        if (hr != S_OK || !supported) return NO;
        if (actualMode) *actualMode = actual;
        // A substituted mode is not the mode that was asked for; the caller must not treat it as a yes.
        return actual == bmdModeUnknown || actual == (BMDDisplayMode)displayMode;
    } catch (...) {
        return NO;
    }
}

- (BOOL)enableDisplayMode:(uint32_t)displayMode width:(int32_t)width height:(int32_t)height
            frameDuration:(int64_t)frameDuration timeScale:(int64_t)timeScale
                   keying:(BOOL)keying keyerLevel:(uint8_t)keyerLevel error:(NSError**)error {
    try {
        if (width <= 0 || height <= 0 || frameDuration <= 0 || timeScale <= 0) return Fail(error, DLBErrorBadArgument, @"The video mode has no size or frame rate.");
        ComPtr<IDeckLinkOutput> out;
        ComPtr<IDeckLinkKeyer> keyer;
        {
            std::lock_guard<std::mutex> lock(_state->mutex);
            if (_state->closed) return Fail(error, DLBErrorBadState, @"This SDI output was closed.");
            if (_state->removed) return Fail(error, DLBErrorDeviceRemoved, @"The SDI card was disconnected.");
            if (_state->enabled) return Fail(error, DLBErrorBadState, @"This SDI output is already enabled.");
            out = _state->output;
            keyer = _state->keyer;
        }
        if (keying && !keyer) return Fail(error, DLBErrorNotSupported, @"This connector has no keyer in the current profile.");
        if (![self supportsDisplayMode:displayMode keying:keying actualMode:nullptr]) {
            return Fail(error, DLBErrorNotSupported, keying ? @"The card does not support this video mode with fill and key."
                                                            : @"The card does not support this video mode on this connector.");
        }

        // The SDK's own description of the mode must agree with what the caller expects, in particular 59.94 versus 60.
        ComPtr<IDeckLinkDisplayMode> description;
        if (out->GetDisplayMode((BMDDisplayMode)displayMode, description.put()) != S_OK || !description) {
            return Fail(error, DLBErrorNotSupported, @"The card does not describe this video mode.");
        }
        BMDTimeValue sdkDuration = 0;
        BMDTimeScale sdkScale = 0;
        description->GetFrameRate(&sdkDuration, &sdkScale);
        const bool sameSize = description->GetWidth() == width && description->GetHeight() == height;
        // Compare the two rationals duration/scale exactly, by cross-multiplication.
        const bool sameRate = sdkScale > 0 && (__int128)sdkDuration * timeScale == (__int128)frameDuration * sdkScale;
        if (!sameSize || !sameRate) {
            return Fail(error, DLBErrorNotSupported, [NSString stringWithFormat:@"The card's video mode is %ldx%ld at %lld/%lld, not the requested %dx%d at %lld/%lld.",
                                                      (long)description->GetWidth(), (long)description->GetHeight(), (long long)sdkDuration, (long long)sdkScale,
                                                      width, height, (long long)frameDuration, (long long)timeScale]);
        }

        int32_t rowBytes = 0;
        HRESULT hr = out->RowBytesForPixelFormat(bmdFormat8BitBGRA, width, &rowBytes);
        if (hr != S_OK || rowBytes < width * 4) return FailHR(error, hr == S_OK ? E_FAIL : hr, @"The card did not give a row size for BGRA frames.");

        // Sequence from manual 2.4.8: EnableVideoOutput, keyer on, completion callback, then preroll.
        hr = out->EnableVideoOutput((BMDDisplayMode)displayMode, bmdVideoOutputFlagDefault);
        if (hr != S_OK) return FailHR(error, hr, @"The card would not enable the video output.");
        bool keyerOn = false;
        if (keying) {
            hr = keyer->Enable(true);
            if (hr != S_OK) {
                out->DisableVideoOutput();
                return FailHR(error, hr, @"The card would not turn on the external keyer.");
            }
            keyerOn = true;
            keyer->SetLevel(keyerLevel);
        }
        ComPtr<IDeckLinkVideoOutputCallback> callback = ComPtr<IDeckLinkVideoOutputCallback>::adopt(new OutputCallback(_state));
        hr = out->SetScheduledFrameCompletionCallback(callback.get());
        if (hr != S_OK) {
            if (keyerOn) keyer->Disable();
            out->DisableVideoOutput();
            return FailHR(error, hr, @"The card would not accept the frame completion callback.");
        }
        {
            std::lock_guard<std::mutex> lock(_state->mutex);
            _state->callback = callback;
            _state->enabled = true;
            _state->playing = false;
            _state->keyerOn = keyerOn;
            _state->keyerLevel = keyerLevel;
            _state->mode = displayMode;
            _state->width = width;
            _state->height = height;
            _state->rowBytes = rowBytes;
            _state->frameDuration = frameDuration;
            _state->timeScale = timeScale;
            _state->pool.clear();
            _state->scheduled = _state->completed = _state->late = _state->dropped = _state->flushed = _state->unknown = 0;
        }
        return YES;
    } catch (...) {
        return Fail(error, DLBErrorSDKFailure, @"Unexpected failure while enabling the SDI output.");
    }
}

- (BOOL)scheduleBGRA:(const uint8_t*)bgra byteCount:(size_t)byteCount frameIndex:(int64_t)frameIndex
           alphaMode:(DLBAlphaMode)alphaMode error:(NSError**)error {
    try {
        ComPtr<IDeckLinkOutput> out;
        ComPtr<IDeckLinkMutableVideoFrame> frame;
        ComPtr<IDeckLinkVideoBuffer> buffer;
        int32_t width, height, rowBytes;
        int64_t duration, scale;
        size_t slot = SIZE_MAX;
        bool needsNewFrame = false;
        {
            std::lock_guard<std::mutex> lock(_state->mutex);
            if (_state->closed) return Fail(error, DLBErrorBadState, @"This SDI output was closed.");
            if (_state->removed) return Fail(error, DLBErrorDeviceRemoved, @"The SDI card was disconnected.");
            if (!_state->enabled) return Fail(error, DLBErrorBadState, @"The SDI output has not been enabled.");
            out = _state->output;
            width = _state->width; height = _state->height; rowBytes = _state->rowBytes;
            duration = _state->frameDuration; scale = _state->timeScale;
            if (!bgra || byteCount != (size_t)width * (size_t)height * 4) {
                return Fail(error, DLBErrorBadArgument, [NSString stringWithFormat:@"A %dx%d frame needs %zu bytes, got %zu.", width, height, (size_t)width * (size_t)height * 4, byteCount]);
            }
            for (size_t i = 0; i < _state->pool.size(); i++) {
                if (!_state->pool[i].inFlight) { slot = i; break; }
            }
            if (slot == SIZE_MAX) {
                if (_state->pool.size() >= kMaxPoolFrames) return Fail(error, DLBErrorOutOfMemory, @"Too many frames are waiting in the SDI card. The card is not consuming them.");
                needsNewFrame = true;
            } else {
                _state->pool[slot].inFlight = true;
                _state->pool[slot].frameIndex = frameIndex;
                _state->pool[slot].sequence = _state->nextSequence++;
                frame = _state->pool[slot].frame;
                buffer = _state->pool[slot].buffer;
            }
        }
        if (needsNewFrame) {
            ComPtr<IDeckLinkMutableVideoFrame> created;
            HRESULT hr = out->CreateVideoFrame(width, height, rowBytes, bmdFormat8BitBGRA, bmdFrameFlagDefault, created.put());
            if (hr != S_OK || !created) return FailHR(error, hr == S_OK ? E_FAIL : hr, @"The card could not create a video frame.");
            ComPtr<IDeckLinkVideoBuffer> createdBuffer = created.as<IDeckLinkVideoBuffer>(IID_IDeckLinkVideoBuffer);
            if (!createdBuffer) return Fail(error, DLBErrorNotSupported, @"The card's video frame has no accessible buffer.");
            std::lock_guard<std::mutex> lock(_state->mutex);
            if (_state->closed || !_state->enabled) return Fail(error, DLBErrorBadState, @"The SDI output was closed while a frame was being made.");
            PoolEntry entry;
            entry.frame = created;
            entry.buffer = createdBuffer;
            entry.frameIndex = frameIndex;
            entry.sequence = _state->nextSequence++;
            entry.inFlight = true;
            _state->pool.push_back(entry);
            slot = _state->pool.size() - 1;
            frame = created;
            buffer = createdBuffer;
        }

        // The one copy: caller bytes into the SDK's buffer, with the card's row stride.
        auto release = [&] {
            std::lock_guard<std::mutex> lock(_state->mutex);
            if (slot < _state->pool.size()) _state->pool[slot].inFlight = false;
        };
        HRESULT hr = buffer->StartAccess(bmdBufferAccessWrite);
        if (hr != S_OK) { release(); return FailHR(error, hr, @"The card would not give write access to a frame."); }
        void* bytes = nullptr;
        uint64_t size = 0;
        hr = buffer->GetBytes(&bytes);
        buffer->GetSize(&size);
        BOOL packed = NO;
        if (hr == S_OK && bytes != nullptr && size >= (uint64_t)rowBytes * (uint64_t)height) {
            packed = DLBPackBGRA(bgra, (size_t)width * 4, (size_t)width, (size_t)height, static_cast<uint8_t*>(bytes), (size_t)rowBytes, alphaMode);
        }
        buffer->EndAccess(bmdBufferAccessWrite);
        if (!packed) { release(); return Fail(error, DLBErrorSDKFailure, @"The card's frame buffer was missing or too small."); }

        hr = out->ScheduleVideoFrame(static_cast<IDeckLinkVideoFrame*>(frame.get()), frameIndex * duration, duration, scale);
        if (hr != S_OK) {
            release();
            bool removed;
            { std::lock_guard<std::mutex> lock(_state->mutex); removed = _state->removed; }
            if (removed) return Fail(error, DLBErrorDeviceRemoved, @"The SDI card was disconnected.");
            return FailHR(error, hr, @"The card would not accept the frame.");
        }
        { std::lock_guard<std::mutex> lock(_state->mutex); _state->scheduled++; }
        return YES;
    } catch (...) {
        return Fail(error, DLBErrorSDKFailure, @"Unexpected failure while scheduling a frame.");
    }
}

- (BOOL)startPlaybackAtFrame:(int64_t)frameIndex error:(NSError**)error {
    try {
        ComPtr<IDeckLinkOutput> out;
        int64_t duration, scale;
        {
            std::lock_guard<std::mutex> lock(_state->mutex);
            if (_state->closed) return Fail(error, DLBErrorBadState, @"This SDI output was closed.");
            if (_state->removed) return Fail(error, DLBErrorDeviceRemoved, @"The SDI card was disconnected.");
            if (!_state->enabled) return Fail(error, DLBErrorBadState, @"The SDI output has not been enabled.");
            out = _state->output;
            duration = _state->frameDuration; scale = _state->timeScale;
        }
        const HRESULT hr = out->StartScheduledPlayback(frameIndex * duration, scale, 1.0);
        if (hr != S_OK) return FailHR(error, hr, @"The card would not start playback.");
        std::lock_guard<std::mutex> lock(_state->mutex);
        _state->playing = true;
        return YES;
    } catch (...) {
        return Fail(error, DLBErrorSDKFailure, @"Unexpected failure while starting playback.");
    }
}

- (void)stopPlayback {
    try {
        ComPtr<IDeckLinkOutput> out;
        {
            std::lock_guard<std::mutex> lock(_state->mutex);
            if (_state->closed || !_state->enabled) return;
            out = _state->output;
            _state->playing = false;
        }
        // Zero time and zero scale mean "now"; queued frames come back to the handler as flushed.
        out->StopScheduledPlayback(0, nullptr, 0);
    } catch (...) {
    }
}

- (BOOL)setKeyerLevel:(uint8_t)level error:(NSError**)error {
    ComPtr<IDeckLinkKeyer> keyer;
    {
        std::lock_guard<std::mutex> lock(_state->mutex);
        if (!_state->keyerOn || !_state->keyer) return Fail(error, DLBErrorBadState, @"The keyer is not on.");
        keyer = _state->keyer;
        _state->keyerLevel = level;
    }
    const HRESULT hr = keyer->SetLevel(level);
    return hr == S_OK ? YES : FailHR(error, hr, @"The card would not change the keyer level.");
}

- (void)disable {
    try {
        ComPtr<IDeckLinkOutput> out;
        ComPtr<IDeckLinkKeyer> keyer;
        bool keyerOn = false;
        bool wasPlaying = false;
        {
            std::lock_guard<std::mutex> lock(_state->mutex);
            if (!_state->enabled) return;
            out = _state->output;
            keyer = _state->keyer;
            keyerOn = _state->keyerOn;
            wasPlaying = _state->playing;
            _state->enabled = false;
            _state->playing = false;
            _state->keyerOn = false;
        }
        if (wasPlaying) out->StopScheduledPlayback(0, nullptr, 0);
        if (keyerOn && keyer) keyer->Disable();
        out->SetScheduledFrameCompletionCallback(nullptr);
        out->DisableVideoOutput();
        std::lock_guard<std::mutex> lock(_state->mutex);
        _state->pool.clear();
        _state->callback.reset();
    } catch (...) {
    }
}

- (void)close {
    [self disable];
    std::lock_guard<std::mutex> lock(_state->mutex);
    if (_state->closed) return;
    _state->closed = true;
    _state->completionHandler = nil;
    _state->failureHandler = nil;
    _state->output.reset();
    _state->keyer.reset();
    _output.reset();
}

- (void)deviceWasRemoved {
    DLBFailureHandler handler;
    {
        std::lock_guard<std::mutex> lock(_state->mutex);
        if (_state->removed) return;
        _state->removed = true;
        _state->playing = false;
        handler = _state->failureHandler;
    }
    if (handler) handler(MakeError(DLBErrorDeviceRemoved, @"The SDI card was disconnected."));
}

- (NSDictionary<NSString*, id>*)statusSnapshot {
    ComPtr<IDeckLinkOutput> out;
    NSMutableDictionary* d = [NSMutableDictionary dictionary];
    {
        std::lock_guard<std::mutex> lock(_state->mutex);
        d[@"enabled"] = @(_state->enabled);
        d[@"playing"] = @(_state->playing);
        d[@"closed"] = @(_state->closed);
        d[@"removed"] = @(_state->removed);
        d[@"keyerOn"] = @(_state->keyerOn);
        d[@"keyerLevel"] = @(_state->keyerLevel);
        d[@"displayMode"] = FourCCOrNone(_state->mode != 0, _state->mode);
        d[@"width"] = @(_state->width);
        d[@"height"] = @(_state->height);
        d[@"rowBytes"] = @(_state->rowBytes);
        d[@"frameDuration"] = @(_state->frameDuration);
        d[@"timeScale"] = @(_state->timeScale);
        d[@"poolFrames"] = @(_state->pool.size());
        d[@"framesScheduled"] = @(_state->scheduled);
        d[@"framesCompleted"] = @(_state->completed);
        d[@"framesLate"] = @(_state->late);
        d[@"framesDropped"] = @(_state->dropped);
        d[@"framesFlushed"] = @(_state->flushed);
        d[@"framesUnknown"] = @(_state->unknown);
        if (_state->enabled && !_state->closed) out = _state->output;
    }
    if (out) {
        uint32_t buffered = 0;
        if (out->GetBufferedVideoFrameCount(&buffered) == S_OK) d[@"bufferedFrames"] = @(buffered);
        BMDReferenceStatus ref = bmdReferenceUnlocked;
        if (out->GetReferenceStatus(&ref) == S_OK) {
            d[@"referenceLocked"] = @((ref & bmdReferenceLocked) != 0);
            d[@"referenceSupported"] = @((ref & bmdReferenceNotSupportedByHardware) == 0);
        }
    }
    return d;
}

@end

// MARK: - DLBInput

@implementation DLBInput {
    std::shared_ptr<InputState> _state;
    BOOL _supportsDetection;
}

- (instancetype)initWithInput:(ComPtr<IDeckLinkInput>)input supportsDetection:(BOOL)supportsDetection {
    self = [super init];
    if (self) {
        _state = std::make_shared<InputState>();
        _state->input = input;
        _state->queue = dispatch_queue_create("com.worshipflow.decklink.input", DISPATCH_QUEUE_SERIAL);
        _supportsDetection = supportsDetection;
    }
    return self;
}

- (void)dealloc { [self close]; }

#define DLB_HANDLER_PROPERTY(Type, getter, setter, field) \
    - (Type)getter { std::lock_guard<std::mutex> lock(_state->mutex); return _state->field; } \
    - (void)setter:(Type)handler { std::lock_guard<std::mutex> lock(_state->mutex); _state->field = [handler copy]; }

DLB_HANDLER_PROPERTY(DLBInputFrameHandler, frameHandler, setFrameHandler, frameHandler)
DLB_HANDLER_PROPERTY(DLBSignalHandler, signalHandler, setSignalHandler, signalHandler)
DLB_HANDLER_PROPERTY(DLBInputFormatHandler, formatHandler, setFormatHandler, formatHandler)
DLB_HANDLER_PROPERTY(DLBFailureHandler, failureHandler, setFailureHandler, failureHandler)

- (BOOL)isRunning { std::lock_guard<std::mutex> lock(_state->mutex); return _state->running; }
- (BOOL)isClosed { std::lock_guard<std::mutex> lock(_state->mutex); return _state->closed; }

- (BOOL)supportsDisplayMode:(uint32_t)displayMode {
    ComPtr<IDeckLinkInput> input;
    {
        std::lock_guard<std::mutex> lock(_state->mutex);
        if (_state->closed || !_state->input) return NO;
        input = _state->input;
    }
    try {
        bool supported = false;
        BMDDisplayMode actual = bmdModeUnknown;
        const HRESULT hr = input->DoesSupportVideoMode(bmdVideoConnectionUnspecified, (BMDDisplayMode)displayMode, bmdFormat8BitYUV,
                                                       bmdNoVideoInputConversion, bmdSupportedVideoModeDefault, &actual, &supported);
        return hr == S_OK && supported;
    } catch (...) {
        return NO;
    }
}

- (BOOL)startWithInitialDisplayMode:(uint32_t)initialDisplayMode detectFormat:(BOOL)detectFormat error:(NSError**)error {
    try {
        ComPtr<IDeckLinkInput> input;
        {
            std::lock_guard<std::mutex> lock(_state->mutex);
            if (_state->closed) return Fail(error, DLBErrorBadState, @"This SDI input was closed.");
            if (_state->running) return Fail(error, DLBErrorBadState, @"This SDI input is already running.");
            input = _state->input;
        }
        if (detectFormat && !_supportsDetection) return Fail(error, DLBErrorNotSupported, @"This connector cannot detect the input format.");

        bool supported = false;
        BMDDisplayMode actual = bmdModeUnknown;
        const HRESULT support = input->DoesSupportVideoMode(bmdVideoConnectionUnspecified, (BMDDisplayMode)initialDisplayMode, bmdFormat8BitYUV,
                                                            bmdNoVideoInputConversion, bmdSupportedVideoModeDefault, &actual, &supported);
        if (support != S_OK || !supported) return Fail(error, DLBErrorNotSupported, @"The card cannot capture this video mode on this connector.");

        ComPtr<IDeckLinkVideoConversion> conversion = ComPtr<IDeckLinkVideoConversion>::adopt(CreateVideoConversionInstance());
        ComPtr<IDeckLinkInputCallback> callback = ComPtr<IDeckLinkInputCallback>::adopt(new InputCallback(_state));

        // Sequence from manual 2.4.6: callback, enable with detection, start streams.
        HRESULT hr = input->SetCallback(callback.get());
        if (hr != S_OK) return FailHR(error, hr, @"The card would not accept the input callback.");
        const BMDVideoInputFlags flags = detectFormat ? bmdVideoInputEnableFormatDetection : bmdVideoInputFlagDefault;
        hr = input->EnableVideoInput((BMDDisplayMode)initialDisplayMode, bmdFormat8BitYUV, flags);
        if (hr != S_OK) {
            input->SetCallback(nullptr);
            return FailHR(error, hr, @"The card would not enable the video input.");
        }
        {
            std::lock_guard<std::mutex> lock(_state->mutex);
            _state->callback = callback;
            _state->conversion = conversion;
            _state->flags = flags;
            _state->detect = detectFormat;
            _state->mode = initialDisplayMode;
            _state->pixelFormat = bmdFormat8BitYUV;
            _state->signal = -1;
            _state->frames = _state->noSignalFrames = _state->conversions = _state->conversionFailures = _state->formatChanges = 0;
            _state->running = true;
        }
        hr = input->StartStreams();
        if (hr != S_OK) {
            [self stop];
            return FailHR(error, hr, @"The card would not start capture.");
        }
        return YES;
    } catch (...) {
        return Fail(error, DLBErrorSDKFailure, @"Unexpected failure while starting the SDI input.");
    }
}

- (void)stop {
    try {
        ComPtr<IDeckLinkInput> input;
        {
            std::lock_guard<std::mutex> lock(_state->mutex);
            if (!_state->running) return;
            _state->running = false;
            input = _state->input;
        }
        // Take the state lock only briefly above: StopStreams waits for callbacks that themselves take it.
        input->StopStreams();
        input->DisableVideoInput();
        input->SetCallback(nullptr);
        std::lock_guard<std::mutex> lock(_state->mutex);
        _state->callback.reset();
        _state->conversion.reset();
    } catch (...) {
    }
}

- (void)close {
    [self stop];
    std::lock_guard<std::mutex> lock(_state->mutex);
    if (_state->closed) return;
    _state->closed = true;
    _state->frameHandler = nil;
    _state->signalHandler = nil;
    _state->formatHandler = nil;
    _state->failureHandler = nil;
    _state->input.reset();
}

- (void)deviceWasRemoved {
    DLBFailureHandler handler;
    {
        std::lock_guard<std::mutex> lock(_state->mutex);
        if (_state->closed) return;
        handler = _state->failureHandler;
        _state->running = false;
    }
    if (handler) handler(MakeError(DLBErrorDeviceRemoved, @"The SDI card was disconnected."));
}

- (NSDictionary<NSString*, id>*)statusSnapshot {
    NSMutableDictionary* d = [NSMutableDictionary dictionary];
    std::lock_guard<std::mutex> lock(_state->mutex);
    d[@"running"] = @(_state->running);
    d[@"closed"] = @(_state->closed);
    d[@"detectFormat"] = @(_state->detect);
    d[@"signal"] = _state->signal < 0 ? @"unknown" : (_state->signal ? @"present" : @"none");
    d[@"displayMode"] = FourCCOrNone(_state->mode != 0, _state->mode);
    d[@"pixelFormat"] = FourCC(_state->pixelFormat);
    d[@"frames"] = @(_state->frames);
    d[@"noSignalFrames"] = @(_state->noSignalFrames);
    d[@"conversions"] = @(_state->conversions);
    d[@"conversionFailures"] = @(_state->conversionFailures);
    d[@"formatChanges"] = @(_state->formatChanges);
    return d;
}

@end

// MARK: - DLBDevice

namespace {

/// Shared between the device and the profile callback that the SDK keeps a reference to.
struct ProfileState {
    std::mutex mutex;
    std::condition_variable changed;
    uint64_t activations = 0;
    uint32_t lastActivated = 0;
    DLBProfileChangeHandler onActivated;
    void (^refresh)(void) = nil;
};

class ProfileCallback final : public IDeckLinkProfileCallback {
public:
    explicit ProfileCallback(std::shared_ptr<ProfileState> state) : state_(std::move(state)) {}

    HRESULT QueryInterface(REFIID iid, LPVOID* ppv) override {
        if (!ppv) return E_POINTER;
        if (IsIUnknown(iid) || SameIID(iid, IID_IDeckLinkProfileCallback)) {
            *ppv = static_cast<IDeckLinkProfileCallback*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG AddRef() override { return ++refs_; }
    ULONG Release() override {
        ULONG n = --refs_;
        if (n == 0) delete this;
        return n;
    }

    // The profile change is held until this returns, so it must not block.
    HRESULT ProfileChanging(IDeckLinkProfile* /*toBeActivated*/, bool /*streamsWillBeForcedToStop*/) override { return S_OK; }

    HRESULT ProfileActivated(IDeckLinkProfile* activated) override {
        try {
            uint32_t id = 0;
            if (activated) {
                ComPtr<IDeckLinkProfileAttributes> attrs = ComPtr<IDeckLinkProfile>::retain(activated).as<IDeckLinkProfileAttributes>(IID_IDeckLinkProfileAttributes);
                int64_t v = 0;
                if (AttrInt(attrs.get(), BMDDeckLinkProfileID, &v)) id = (uint32_t)v;
            }
            void (^refresh)(void) = nil;
            DLBProfileChangeHandler handler;
            {
                std::lock_guard<std::mutex> lock(state_->mutex);
                state_->lastActivated = id;
                state_->activations++;
                refresh = state_->refresh;
                handler = state_->onActivated;
            }
            state_->changed.notify_all();
            if (refresh) refresh();
            if (handler) handler();
        } catch (...) {
        }
        return S_OK;
    }

private:
    ~ProfileCallback() override = default;
    std::atomic<ULONG> refs_{1};
    std::shared_ptr<ProfileState> state_;
};

}  // namespace

@interface DLBDevice ()
@property (atomic, readwrite, strong) DLBDeviceInfo* info;
@end

@implementation DLBDevice {
    ComPtr<IDeckLink> _deckLink;
    std::shared_ptr<ProfileState> _profile;
    ComPtr<IDeckLinkProfileCallback> _profileCallback;
    BOOL _present;
    NSHashTable<DLBOutput*>* _outputs;
    NSHashTable<DLBInput*>* _inputs;
    NSLock* _lock;
}

- (instancetype)initWithDeckLink:(IDeckLink*)deckLink {
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        _deckLink = ComPtr<IDeckLink>::retain(deckLink);
        _present = YES;
        _outputs = [NSHashTable weakObjectsHashTable];
        _inputs = [NSHashTable weakObjectsHashTable];
        _info = BuildInfo(deckLink);
        _profile = std::make_shared<ProfileState>();
    }
    return self;
}

/// Installs the profile callback on first use. It is not installed at creation: the SDK keeps one callback per device,
/// so short-lived wrapper objects (for example the extra ones a re-scan creates) must not replace the long-lived one.
- (void)ensureProfileCallback {
    [_lock lock];
    if (_profileCallback) { [_lock unlock]; return; }
    ComPtr<IDeckLinkProfileManager> manager = _deckLink.as<IDeckLinkProfileManager>(IID_IDeckLinkProfileManager);
    if (manager) {
        __weak DLBDevice* weakSelf = self;
        {
            std::lock_guard<std::mutex> lock(_profile->mutex);
            _profile->refresh = ^{ [weakSelf refreshInfo]; };
        }
        _profileCallback = ComPtr<IDeckLinkProfileCallback>::adopt(new ProfileCallback(_profile));
        manager->SetCallback(_profileCallback.get());
    }
    [_lock unlock];
}

- (void)dealloc {
    if (_profileCallback) {
        ComPtr<IDeckLinkProfileManager> manager = _deckLink.as<IDeckLinkProfileManager>(IID_IDeckLinkProfileManager);
        if (manager) manager->SetCallback(nullptr);
    }
    if (_profile) {
        std::lock_guard<std::mutex> lock(_profile->mutex);
        _profile->refresh = nil;
        _profile->onActivated = nil;
    }
}

- (IDeckLink*)rawDeckLink { return _deckLink.get(); }

- (BOOL)isPresent { [_lock lock]; BOOL p = _present; [_lock unlock]; return p; }

- (DLBProfileChangeHandler)profileChangeHandler {
    std::lock_guard<std::mutex> lock(_profile->mutex);
    return _profile->onActivated;
}
- (void)setProfileChangeHandler:(DLBProfileChangeHandler)handler {
    std::lock_guard<std::mutex> lock(_profile->mutex);
    _profile->onActivated = [handler copy];
}

- (DLBDeviceInfo*)refreshInfo {
    DLBDeviceInfo* fresh = nil;
    try {
        if (self.isPresent) fresh = BuildInfo(_deckLink.get());
    } catch (...) {
    }
    if (fresh) self.info = fresh;
    return self.info;
}

- (BOOL)activateProfile:(uint32_t)profileID timeout:(NSTimeInterval)timeout error:(NSError**)error {
    try {
        if (!self.isPresent) return Fail(error, DLBErrorDeviceRemoved, @"The SDI card was disconnected.");
        ComPtr<IDeckLinkProfileManager> manager = _deckLink.as<IDeckLinkProfileManager>(IID_IDeckLinkProfileManager);
        if (!manager) {
            // One profile only. Asking for that one is a success; anything else is not available.
            DLBDeviceInfo* i = self.info;
            if (i.hasActiveProfile && i.activeProfileID == profileID) return YES;
            return Fail(error, DLBErrorNotSupported, @"This card has only one profile.");
        }
        [self ensureProfileCallback];
        ComPtr<IDeckLinkProfile> profile;
        HRESULT hr = manager->GetProfile((BMDProfileID)profileID, profile.put());
        if (hr != S_OK || !profile) return Fail(error, DLBErrorNotSupported, @"This card does not offer that profile.");
        bool active = false;
        if (profile->IsActive(&active) == S_OK && active) return YES;

        uint64_t before;
        {
            std::lock_guard<std::mutex> lock(_profile->mutex);
            before = _profile->activations;
            _profile->lastActivated = 0;
        }
        hr = profile->SetActive();
        if (hr != S_OK) return FailHR(error, hr, @"The card would not switch profile.");

        // Activation is complete only when the profile callback reports it.
        std::unique_lock<std::mutex> lock(_profile->mutex);
        const bool done = _profile->changed.wait_for(lock, std::chrono::duration<double>(timeout), [&] {
            return _profile->activations > before && _profile->lastActivated == profileID;
        });
        lock.unlock();
        if (!done) {
            bool nowActive = false;
            if (profile->IsActive(&nowActive) == S_OK && nowActive) { [self refreshInfo]; return YES; }
            return Fail(error, DLBErrorProfileTimeout, @"The card did not finish switching profile in time.");
        }
        [self refreshInfo];
        return YES;
    } catch (...) {
        return Fail(error, DLBErrorSDKFailure, @"Unexpected failure while switching profile.");
    }
}

- (nullable DLBOutput*)openOutputWithError:(NSError**)error {
    try {
        if (!self.isPresent) { Fail(error, DLBErrorDeviceRemoved, @"The SDI card was disconnected."); return nil; }
        ComPtr<IDeckLinkOutput> out = _deckLink.as<IDeckLinkOutput>(IID_IDeckLinkOutput);
        if (!out) { Fail(error, DLBErrorNotSupported, @"This connector cannot play video in the card's current profile."); return nil; }
        ComPtr<IDeckLinkKeyer> keyer = _deckLink.as<IDeckLinkKeyer>(IID_IDeckLinkKeyer);
        DLBOutput* output = [[DLBOutput alloc] initWithOutput:out keyer:keyer];
        [_lock lock];
        [_outputs addObject:output];
        [_lock unlock];
        return output;
    } catch (...) {
        Fail(error, DLBErrorSDKFailure, @"Unexpected failure while opening the SDI output.");
        return nil;
    }
}

- (nullable DLBInput*)openInputWithError:(NSError**)error {
    try {
        if (!self.isPresent) { Fail(error, DLBErrorDeviceRemoved, @"The SDI card was disconnected."); return nil; }
        ComPtr<IDeckLinkInput> in = _deckLink.as<IDeckLinkInput>(IID_IDeckLinkInput);
        if (!in) { Fail(error, DLBErrorNotSupported, @"This connector cannot capture video in the card's current profile."); return nil; }
        DLBInput* input = [[DLBInput alloc] initWithInput:in supportsDetection:self.info.supportsInputFormatDetection];
        [_lock lock];
        [_inputs addObject:input];
        [_lock unlock];
        return input;
    } catch (...) {
        Fail(error, DLBErrorSDKFailure, @"Unexpected failure while opening the SDI input.");
        return nil;
    }
}

- (void)markRemoved {
    NSArray<DLBOutput*>* outputs;
    NSArray<DLBInput*>* inputs;
    [_lock lock];
    if (!_present) { [_lock unlock]; return; }
    _present = NO;
    outputs = _outputs.allObjects;
    inputs = _inputs.allObjects;
    [_lock unlock];
    for (DLBOutput* o in outputs) [o deviceWasRemoved];
    for (DLBInput* i in inputs) [i deviceWasRemoved];
}

- (NSDictionary<NSString*, id>*)statusSnapshot {
    NSMutableDictionary* d = [NSMutableDictionary dictionaryWithDictionary:self.info.snapshot];
    d[@"present"] = @(self.isPresent);
    [_lock lock];
    NSArray<DLBOutput*>* outputs = _outputs.allObjects;
    NSArray<DLBInput*>* inputs = _inputs.allObjects;
    [_lock unlock];
    NSMutableArray* o = [NSMutableArray array];
    for (DLBOutput* x in outputs) [o addObject:x.statusSnapshot];
    NSMutableArray* i = [NSMutableArray array];
    for (DLBInput* x in inputs) [i addObject:x.statusSnapshot];
    d[@"outputs"] = o;
    d[@"inputs"] = i;
    return d;
}

@end

// MARK: - Discovery

namespace {

struct DiscoveryState {
    std::mutex mutex;
    NSMutableArray<DLBDevice*>* devices = [NSMutableArray array];
    void (^arrived)(DLBDevice*) = nil;
    void (^removed)(DLBDevice*) = nil;
};

DLBDevice* FindKnown(NSArray<DLBDevice*>* known, IDeckLink* dl) {
    DLBDeviceInfo* probe = BuildInfo(dl);
    for (DLBDevice* d in known) {
        if (probe.hasPersistentID && d.info.hasPersistentID && d.info.persistentID == probe.persistentID) return d;
    }
    for (DLBDevice* d in known) {
        if ([d rawDeckLink] == dl) return d;
    }
    return nil;
}

class DiscoveryCallback final : public IDeckLinkDeviceNotificationCallback {
public:
    explicit DiscoveryCallback(std::shared_ptr<DiscoveryState> state) : state_(std::move(state)) {}

    HRESULT QueryInterface(REFIID iid, LPVOID* ppv) override {
        if (!ppv) return E_POINTER;
        if (IsIUnknown(iid) || SameIID(iid, IID_IDeckLinkDeviceNotificationCallback)) {
            *ppv = static_cast<IDeckLinkDeviceNotificationCallback*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG AddRef() override { return ++refs_; }
    ULONG Release() override {
        ULONG n = --refs_;
        if (n == 0) delete this;
        return n;
    }

    HRESULT DeckLinkDeviceArrived(IDeckLink* deckLink) override {
        try {
            if (!deckLink) return S_OK;
            void (^handler)(DLBDevice*) = nil;
            DLBDevice* device = nil;
            {
                std::lock_guard<std::mutex> lock(state_->mutex);
                if (FindKnown(state_->devices, deckLink)) return S_OK;
                device = [[DLBDevice alloc] initWithDeckLink:deckLink];
                [state_->devices addObject:device];
                handler = state_->arrived;
            }
            if (handler && device) handler(device);
        } catch (...) {
        }
        return S_OK;
    }

    HRESULT DeckLinkDeviceRemoved(IDeckLink* deckLink) override {
        try {
            if (!deckLink) return S_OK;
            void (^handler)(DLBDevice*) = nil;
            DLBDevice* device = nil;
            {
                std::lock_guard<std::mutex> lock(state_->mutex);
                device = FindKnown(state_->devices, deckLink);
                if (device) [state_->devices removeObject:device];
                handler = state_->removed;
            }
            if (device) {
                [device markRemoved];
                if (handler) handler(device);
            }
        } catch (...) {
        }
        return S_OK;
    }

private:
    ~DiscoveryCallback() override = default;
    std::atomic<ULONG> refs_{1};
    std::shared_ptr<DiscoveryState> state_;
};

}  // namespace

@implementation DLBDiscovery {
    std::shared_ptr<DiscoveryState> _state;
    ComPtr<IDeckLinkDiscovery> _discovery;
    ComPtr<IDeckLinkDeviceNotificationCallback> _callback;
    BOOL _started;
    NSLock* _lock;
}

- (instancetype)initWithArrived:(void (^)(DLBDevice*))arrived removed:(void (^)(DLBDevice*))removed {
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        _state = std::make_shared<DiscoveryState>();
        _state->arrived = [arrived copy];
        _state->removed = [removed copy];
    }
    return self;
}

- (void)dealloc { [self stop]; }

- (NSArray<DLBDevice*>*)devices {
    std::lock_guard<std::mutex> lock(_state->mutex);
    return [_state->devices copy];
}

- (BOOL)startWithError:(NSError**)error {
    try {
        [_lock lock];
        BOOL already = _started;
        [_lock unlock];
        if (already) return YES;
        ComPtr<IDeckLinkDiscovery> discovery = ComPtr<IDeckLinkDiscovery>::adopt(CreateDeckLinkDiscoveryInstance());
        if (!discovery) return Fail(error, DLBErrorDriverNotInstalled, DriverMissingMessage());
        ComPtr<IDeckLinkDeviceNotificationCallback> callback = ComPtr<IDeckLinkDeviceNotificationCallback>::adopt(new DiscoveryCallback(_state));
        const HRESULT hr = discovery->InstallDeviceNotifications(callback.get());
        if (hr != S_OK) return FailHR(error, hr, @"The driver would not start device notifications.");
        [_lock lock];
        _discovery = discovery;
        _callback = callback;
        _started = YES;
        [_lock unlock];
        return YES;
    } catch (...) {
        return Fail(error, DLBErrorSDKFailure, @"Unexpected failure while starting device discovery.");
    }
}

- (void)stop {
    try {
        ComPtr<IDeckLinkDiscovery> discovery;
        [_lock lock];
        if (_started) { discovery = _discovery; _discovery.reset(); _callback.reset(); _started = NO; }
        [_lock unlock];
        if (discovery) discovery->UninstallDeviceNotifications();
        std::lock_guard<std::mutex> lock(_state->mutex);
        _state->arrived = nil;
        _state->removed = nil;
    } catch (...) {
    }
}

@end

// MARK: - DLBBridge

@implementation DLBBridge

+ (NSArray<DLBDevice*>*)enumerateDevices {
    NSMutableArray<DLBDevice*>* devices = [NSMutableArray array];
    try {
        ComPtr<IDeckLinkIterator> it = ComPtr<IDeckLinkIterator>::adopt(CreateDeckLinkIteratorInstance());
        if (!it) return devices;
        for (;;) {
            ComPtr<IDeckLink> dl;
            if (it->Next(dl.put()) != S_OK || !dl) break;
            [devices addObject:[[DLBDevice alloc] initWithDeckLink:dl.get()]];
        }
    } catch (...) {
    }
    return devices;
}

+ (NSDictionary<NSString*, id>*)statusSnapshot {
    DLBDriverInfo* driver = [DLBDriverInfo current];
    NSMutableArray* devices = [NSMutableArray array];
    for (DLBDevice* d in [self enumerateDevices]) [devices addObject:d.statusSnapshot];
    return @{
        @"driverPresent": @(driver.present),
        @"apiVersion": driver.apiVersionString ?: (id)[NSNull null],
        @"apiVersionRaw": @(driver.apiVersionRaw),
        @"compiledAPIVersion": DLBDriverInfo.compiledAPIVersionString,
        @"devices": devices,
    };
}

@end
