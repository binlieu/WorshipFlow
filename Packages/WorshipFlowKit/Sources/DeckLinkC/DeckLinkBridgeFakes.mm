// FIX-C: stand-ins for the SDK's objects, for tests only (see include/DeckLinkBridgeTesting.h). They implement the
// interfaces exactly as declared in sdk/, answer E_NOTIMPL for everything the bridge logic under test does not use, and
// record what the bridge calls.
#import "DeckLinkBridgeTesting.h"

#include "DeckLinkAPI.h"
#include "DeckLinkBridgeFakes.h"

#include <atomic>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

IDeckLinkVideoConversion* (*DLBConversionFactory)(void) = &CreateVideoConversionInstance;

namespace {

bool SameID(REFIID a, REFIID b) { return std::memcmp(&a, &b, sizeof(CFUUIDBytes)) == 0; }
bool IsUnknown(REFIID iid) {
    CFUUIDBytes bytes = CFUUIDGetUUIDBytes(IUnknownUUID);
    return SameID(iid, bytes);
}

/// Reference counting and QueryInterface for one interface `I` with id `iid`.
template <class I>
class FakeCom : public I {
public:
    virtual ~FakeCom() = default;
    HRESULT QueryInterface(REFIID iid, LPVOID* ppv) override {
        if (!ppv) return E_POINTER;
        if (IsUnknown(iid) || SameID(iid, interfaceID())) {
            *ppv = static_cast<I*>(this);
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
protected:
    virtual REFIID interfaceID() const = 0;
private:
    std::atomic<ULONG> refs_{1};
};

struct Log {
    std::mutex mutex;
    std::vector<std::string> items;
    void add(const std::string& s) { std::lock_guard<std::mutex> l(mutex); items.push_back(s); }
    NSArray<NSString*>* snapshot() {
        std::lock_guard<std::mutex> l(mutex);
        NSMutableArray* out = [NSMutableArray array];
        for (const auto& s : items) [out addObject:[NSString stringWithUTF8String:s.c_str()]];
        return out;
    }
    void clear() { std::lock_guard<std::mutex> l(mutex); items.clear(); }
};

const char* FormatName(BMDPixelFormat f) { return f == bmdFormat8BitBGRA ? "BGRA" : (f == bmdFormat8BitYUV ? "YUV" : "other"); }

// MARK: Display mode

class FakeMode final : public FakeCom<IDeckLinkDisplayMode> {
public:
    FakeMode(BMDDisplayMode mode, long w, long h) : mode_(mode), w_(w), h_(h) {}
    HRESULT GetName(CFStringRef* name) override { *name = CFStringCreateCopy(nullptr, CFSTR("fake")); return S_OK; }
    BMDDisplayMode GetDisplayMode() override { return mode_; }
    long GetWidth() override { return w_; }
    long GetHeight() override { return h_; }
    HRESULT GetFrameRate(BMDTimeValue* d, BMDTimeScale* s) override { *d = 1001; *s = 60000; return S_OK; }
    BMDFieldDominance GetFieldDominance() override { return bmdProgressiveFrame; }
    BMDDisplayModeFlags GetFlags() override { return 0; }
protected:
    REFIID interfaceID() const override { return IID_IDeckLinkDisplayMode; }
private:
    BMDDisplayMode mode_;
    long w_, h_;
};

// MARK: Input

class FakeInput final : public FakeCom<IDeckLinkInput> {
public:
    std::mutex mutex;
    Log log;
    bool bgra = true, yuv = true;
    std::vector<std::pair<std::string, HRESULT>> failures;
    IDeckLinkInputCallback* callback = nullptr;

    ~FakeInput() override { if (callback) callback->Release(); }

    HRESULT result(const char* name) {
        std::lock_guard<std::mutex> l(mutex);
        for (const auto& f : failures) if (f.first == name) return f.second;
        return S_OK;
    }
    HRESULT DoesSupportVideoMode(BMDVideoConnection, BMDDisplayMode, BMDPixelFormat fmt, BMDVideoInputConversionMode, BMDSupportedVideoModeFlags,
                                 BMDDisplayMode* actual, bool* supported) override {
        std::lock_guard<std::mutex> l(mutex);
        if (actual) *actual = bmdModeUnknown;
        *supported = fmt == bmdFormat8BitBGRA ? bgra : (fmt == bmdFormat8BitYUV ? yuv : false);
        return S_OK;
    }
    HRESULT GetDisplayMode(BMDDisplayMode, IDeckLinkDisplayMode**) override { return E_NOTIMPL; }
    HRESULT GetDisplayModeIterator(IDeckLinkDisplayModeIterator**) override { return E_NOTIMPL; }
    HRESULT SetScreenPreviewCallback(IDeckLinkScreenPreviewCallback*) override { return E_NOTIMPL; }
    HRESULT EnableVideoInput(BMDDisplayMode, BMDPixelFormat fmt, BMDVideoInputFlags) override {
        log.add(std::string("EnableVideoInput(") + FormatName(fmt) + ")");
        return result("EnableVideoInput");
    }
    HRESULT EnableVideoInputWithAllocatorProvider(BMDDisplayMode, BMDPixelFormat, BMDVideoInputFlags, IDeckLinkVideoBufferAllocatorProvider*) override { return E_NOTIMPL; }
    HRESULT DisableVideoInput() override { log.add("DisableVideoInput"); return result("DisableVideoInput"); }
    HRESULT GetAvailableVideoFrameCount(uint32_t*) override { return E_NOTIMPL; }
    HRESULT EnableAudioInput(BMDAudioSampleRate, BMDAudioSampleType, uint32_t) override { return E_NOTIMPL; }
    HRESULT DisableAudioInput() override { return E_NOTIMPL; }
    HRESULT GetAvailableAudioSampleFrameCount(uint32_t*) override { return E_NOTIMPL; }
    HRESULT StartStreams() override { log.add("StartStreams"); return result("StartStreams"); }
    HRESULT StopStreams() override { log.add("StopStreams"); return result("StopStreams"); }
    HRESULT PauseStreams() override { log.add("PauseStreams"); return result("PauseStreams"); }
    HRESULT FlushStreams() override { log.add("FlushStreams"); return result("FlushStreams"); }
    HRESULT SetCallback(IDeckLinkInputCallback* cb) override {
        log.add(cb ? "SetCallback(set)" : "SetCallback(null)");
        std::lock_guard<std::mutex> l(mutex);
        if (cb) cb->AddRef();
        if (callback) callback->Release();
        callback = cb;
        return S_OK;
    }
    HRESULT GetHardwareReferenceClock(BMDTimeScale, BMDTimeValue*, BMDTimeValue*, BMDTimeValue*) override { return E_NOTIMPL; }
protected:
    REFIID interfaceID() const override { return IID_IDeckLinkInput; }
};

// MARK: Output and keyer

class FakeKeyer final : public FakeCom<IDeckLinkKeyer> {
public:
    FakeKeyer(std::shared_ptr<Log> log, std::atomic<int32_t>* enableResult, std::atomic<int32_t>* levelResult)
        : log_(std::move(log)), enable_(enableResult), level_(levelResult) {}
    HRESULT Enable(bool) override { log_->add("Keyer.Enable"); return (HRESULT)enable_->load(); }
    HRESULT SetLevel(uint8_t level) override { log_->add("Keyer.SetLevel(" + std::to_string(level) + ")"); return (HRESULT)level_->load(); }
    HRESULT RampUp(uint32_t) override { return E_NOTIMPL; }
    HRESULT RampDown(uint32_t) override { return E_NOTIMPL; }
    HRESULT Disable() override { log_->add("Keyer.Disable"); return S_OK; }
protected:
    REFIID interfaceID() const override { return IID_IDeckLinkKeyer; }
private:
    std::shared_ptr<Log> log_;
    std::atomic<int32_t>* enable_;
    std::atomic<int32_t>* level_;
};

class FakeOutput final : public FakeCom<IDeckLinkOutput> {
public:
    explicit FakeOutput(std::shared_ptr<Log> log) : log_(std::move(log)) {}
    HRESULT DoesSupportVideoMode(BMDVideoConnection, BMDDisplayMode, BMDPixelFormat, BMDVideoOutputConversionMode, BMDSupportedVideoModeFlags,
                                 BMDDisplayMode* actual, bool* supported) override {
        if (actual) *actual = bmdModeUnknown;
        *supported = true;
        return S_OK;
    }
    HRESULT GetDisplayMode(BMDDisplayMode mode, IDeckLinkDisplayMode** out) override { *out = new FakeMode(mode, 1920, 1080); return S_OK; }
    HRESULT GetDisplayModeIterator(IDeckLinkDisplayModeIterator**) override { return E_NOTIMPL; }
    HRESULT SetScreenPreviewCallback(IDeckLinkScreenPreviewCallback*) override { return E_NOTIMPL; }
    HRESULT EnableVideoOutput(BMDDisplayMode, BMDVideoOutputFlags) override { log_->add("EnableVideoOutput"); return S_OK; }
    HRESULT DisableVideoOutput() override { log_->add("DisableVideoOutput"); return S_OK; }
    HRESULT CreateVideoFrame(int32_t, int32_t, int32_t, BMDPixelFormat, BMDFrameFlags, IDeckLinkMutableVideoFrame**) override { return E_NOTIMPL; }
    HRESULT CreateVideoFrameWithBuffer(int32_t, int32_t, int32_t, BMDPixelFormat, BMDFrameFlags, IDeckLinkVideoBuffer*, IDeckLinkMutableVideoFrame**) override { return E_NOTIMPL; }
    HRESULT RowBytesForPixelFormat(BMDPixelFormat, int32_t width, int32_t* rowBytes) override { *rowBytes = width * 4; return S_OK; }
    HRESULT CreateAncillaryData(BMDPixelFormat, IDeckLinkVideoFrameAncillary**) override { return E_NOTIMPL; }
    HRESULT DisplayVideoFrameSync(IDeckLinkVideoFrame*) override { return E_NOTIMPL; }
    HRESULT ScheduleVideoFrame(IDeckLinkVideoFrame*, BMDTimeValue, BMDTimeValue, BMDTimeScale) override { return E_NOTIMPL; }
    HRESULT SetScheduledFrameCompletionCallback(IDeckLinkVideoOutputCallback* cb) override {
        log_->add(cb ? "SetScheduledFrameCompletionCallback(set)" : "SetScheduledFrameCompletionCallback(null)");
        return S_OK;
    }
    HRESULT GetBufferedVideoFrameCount(uint32_t*) override { return E_NOTIMPL; }
    HRESULT EnableAudioOutput(BMDAudioSampleRate, BMDAudioSampleType, uint32_t, BMDAudioOutputStreamType) override { return E_NOTIMPL; }
    HRESULT DisableAudioOutput() override { return E_NOTIMPL; }
    HRESULT WriteAudioSamplesSync(void*, uint32_t, uint32_t*) override { return E_NOTIMPL; }
    HRESULT BeginAudioPreroll() override { return E_NOTIMPL; }
    HRESULT EndAudioPreroll() override { return E_NOTIMPL; }
    HRESULT ScheduleAudioSamples(void*, uint32_t, BMDTimeValue, BMDTimeScale, uint32_t*) override { return E_NOTIMPL; }
    HRESULT GetBufferedAudioSampleFrameCount(uint32_t*) override { return E_NOTIMPL; }
    HRESULT FlushBufferedAudioSamples() override { return E_NOTIMPL; }
    HRESULT SetAudioCallback(IDeckLinkAudioOutputCallback*) override { return E_NOTIMPL; }
    HRESULT StartScheduledPlayback(BMDTimeValue, BMDTimeScale, double) override { return E_NOTIMPL; }
    HRESULT StopScheduledPlayback(BMDTimeValue, BMDTimeValue*, BMDTimeScale) override { log_->add("StopScheduledPlayback"); return S_OK; }
    HRESULT IsScheduledPlaybackRunning(bool*) override { return E_NOTIMPL; }
    HRESULT GetScheduledStreamTime(BMDTimeScale, BMDTimeValue*, double*) override { return E_NOTIMPL; }
    HRESULT GetReferenceStatus(BMDReferenceStatus*) override { return E_NOTIMPL; }
    HRESULT GetHardwareReferenceClock(BMDTimeScale, BMDTimeValue*, BMDTimeValue*, BMDTimeValue*) override { return E_NOTIMPL; }
    HRESULT GetFrameCompletionReferenceTimestamp(IDeckLinkVideoFrame*, BMDTimeScale, BMDTimeValue*) override { return E_NOTIMPL; }
protected:
    REFIID interfaceID() const override { return IID_IDeckLinkOutput; }
private:
    std::shared_ptr<Log> log_;
};

// MARK: Device with a profile manager

thread_local bool gInsideProfileCallback = false;

struct DeviceCounters {
    std::atomic<NSInteger> getProfiles{0};
    std::atomic<NSInteger> getProfilesInside{0};
    std::mutex mutex;
    IDeckLinkProfileCallback* callback = nullptr;
};

class FakeProfile final : public FakeCom<IDeckLinkProfile> {
public:
    HRESULT GetDevice(IDeckLink**) override { return E_NOTIMPL; }
    HRESULT IsActive(bool* active) override { *active = true; return S_OK; }
    HRESULT SetActive() override { return S_OK; }
    HRESULT GetPeers(IDeckLinkProfileIterator**) override { return E_NOTIMPL; }
protected:
    REFIID interfaceID() const override { return IID_IDeckLinkProfile; }
};

class FakeProfileIterator final : public FakeCom<IDeckLinkProfileIterator> {
public:
    HRESULT Next(IDeckLinkProfile** profile) override {
        if (given_) { *profile = nullptr; return S_FALSE; }
        given_ = true;
        *profile = new FakeProfile();
        return S_OK;
    }
protected:
    REFIID interfaceID() const override { return IID_IDeckLinkProfileIterator; }
private:
    bool given_ = false;
};

class FakeProfileManager final : public FakeCom<IDeckLinkProfileManager> {
public:
    explicit FakeProfileManager(std::shared_ptr<DeviceCounters> c) : c_(std::move(c)) {}
    HRESULT GetProfiles(IDeckLinkProfileIterator** it) override {
        c_->getProfiles++;
        if (gInsideProfileCallback) c_->getProfilesInside++;
        *it = new FakeProfileIterator();
        return S_OK;
    }
    HRESULT GetProfile(BMDProfileID, IDeckLinkProfile** p) override { *p = new FakeProfile(); return S_OK; }
    HRESULT SetCallback(IDeckLinkProfileCallback* cb) override {
        std::lock_guard<std::mutex> l(c_->mutex);
        if (cb) cb->AddRef();
        if (c_->callback) c_->callback->Release();
        c_->callback = cb;
        return S_OK;
    }
protected:
    REFIID interfaceID() const override { return IID_IDeckLinkProfileManager; }
private:
    std::shared_ptr<DeviceCounters> c_;
};

struct DeviceFacts {
    std::string model = "Fake DeckLink";
    int64_t subDeviceIndex = 0;
    uint32_t activeProfile = 0;
};

class FakeAttributes final : public FakeCom<IDeckLinkProfileAttributes> {
public:
    explicit FakeAttributes(DeviceFacts f) : f_(std::move(f)) {}
    HRESULT GetFlag(BMDDeckLinkAttributeID, bool*) override { return E_NOTIMPL; }
    HRESULT GetInt(BMDDeckLinkAttributeID id, int64_t* v) override {
        if (id == BMDDeckLinkSubDeviceIndex) { *v = f_.subDeviceIndex; return S_OK; }
        if (id == BMDDeckLinkProfileID && f_.activeProfile != 0) { *v = f_.activeProfile; return S_OK; }
        return E_NOTIMPL;
    }
    HRESULT GetFloat(BMDDeckLinkAttributeID, double*) override { return E_NOTIMPL; }
    HRESULT GetString(BMDDeckLinkAttributeID, CFStringRef*) override { return E_NOTIMPL; }
    HRESULT GetStringWithParam(BMDDeckLinkAttributeID, uint64_t, CFStringRef*) override { return E_NOTIMPL; }
protected:
    REFIID interfaceID() const override { return IID_IDeckLinkProfileAttributes; }
private:
    DeviceFacts f_;
};

class FakeDeckLink final : public IDeckLink {
public:
    explicit FakeDeckLink(std::shared_ptr<DeviceCounters> c, DeviceFacts facts = DeviceFacts()) : c_(std::move(c)), facts_(std::move(facts)) {}
    HRESULT QueryInterface(REFIID iid, LPVOID* ppv) override {
        if (!ppv) return E_POINTER;
        if (IsUnknown(iid) || SameID(iid, IID_IDeckLink)) { *ppv = static_cast<IDeckLink*>(this); AddRef(); return S_OK; }
        if (SameID(iid, IID_IDeckLinkProfileManager)) { *ppv = static_cast<IDeckLinkProfileManager*>(new FakeProfileManager(c_)); return S_OK; }
        if (SameID(iid, IID_IDeckLinkProfileAttributes)) { *ppv = static_cast<IDeckLinkProfileAttributes*>(new FakeAttributes(facts_)); return S_OK; }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG AddRef() override { return ++refs_; }
    ULONG Release() override { ULONG n = --refs_; if (n == 0) delete this; return n; }
    HRESULT GetModelName(CFStringRef* name) override { *name = CFStringCreateWithCString(nullptr, facts_.model.c_str(), kCFStringEncodingUTF8); return S_OK; }
    HRESULT GetDisplayName(CFStringRef* name) override { *name = CFStringCreateWithCString(nullptr, facts_.model.c_str(), kCFStringEncodingUTF8); return S_OK; }
    ~FakeDeckLink() override {
        std::lock_guard<std::mutex> l(c_->mutex);
        if (c_->callback) { c_->callback->Release(); c_->callback = nullptr; }
    }
private:
    std::atomic<ULONG> refs_{1};
    std::shared_ptr<DeviceCounters> c_;
    DeviceFacts facts_;
};

class FakeConversion final : public FakeCom<IDeckLinkVideoConversion> {
public:
    HRESULT ConvertFrame(IDeckLinkVideoFrame*, IDeckLinkVideoFrame*) override { return E_NOTIMPL; }
    HRESULT ConvertNewFrame(IDeckLinkVideoFrame*, BMDPixelFormat, BMDColorspace, IDeckLinkVideoBuffer*, IDeckLinkVideoFrame**) override { return E_NOTIMPL; }
protected:
    REFIID interfaceID() const override { return IID_IDeckLinkVideoConversion; }
};

}  // namespace

IDeckLinkVideoConversion* DLBNewFakeConversion(void) { return new FakeConversion(); }

// MARK: - Objective-C wrappers

@implementation DLBFakeInput {
    FakeInput* _impl;
}
- (instancetype)init {
    self = [super init];
    if (self) _impl = new FakeInput();
    return self;
}
- (void)dealloc { if (_impl) _impl->Release(); }
- (BOOL)bgraSupported { std::lock_guard<std::mutex> l(_impl->mutex); return _impl->bgra; }
- (void)setBgraSupported:(BOOL)v { std::lock_guard<std::mutex> l(_impl->mutex); _impl->bgra = v; }
- (BOOL)yuvSupported { std::lock_guard<std::mutex> l(_impl->mutex); return _impl->yuv; }
- (void)setYuvSupported:(BOOL)v { std::lock_guard<std::mutex> l(_impl->mutex); _impl->yuv = v; }
- (void)failCall:(NSString*)name withResult:(int32_t)result {
    std::lock_guard<std::mutex> l(_impl->mutex);
    _impl->failures.emplace_back(std::string(name.UTF8String), (HRESULT)result);
}
- (NSArray<NSString*>*)calls { return _impl->log.snapshot(); }
- (void)clearCalls { _impl->log.clear(); }
- (BOOL)callbackInstalled { std::lock_guard<std::mutex> l(_impl->mutex); return _impl->callback != nullptr; }
- (void)sendFormatChange:(uint32_t)displayMode width:(int32_t)width height:(int32_t)height rgb444:(BOOL)rgb444 {
    IDeckLinkInputCallback* cb = nullptr;
    {
        std::lock_guard<std::mutex> l(_impl->mutex);
        cb = _impl->callback;
        if (cb) cb->AddRef();
    }
    if (!cb) return;
    FakeMode* mode = new FakeMode((BMDDisplayMode)displayMode, width, height);
    cb->VideoInputFormatChanged(bmdVideoInputDisplayModeChanged, mode, rgb444 ? bmdDetectedVideoInputRGB444 : bmdDetectedVideoInputYCbCr422);
    mode->Release();
    cb->Release();
}
- (void*)rawInterface { return static_cast<IDeckLinkInput*>(_impl); }
@end

@implementation DLBFakeOutput {
    std::shared_ptr<Log> _log;
    std::atomic<int32_t>* _enable;
    std::atomic<int32_t>* _level;
    FakeOutput* _output;
    FakeKeyer* _keyer;
}
- (instancetype)init {
    self = [super init];
    if (self) {
        _log = std::make_shared<Log>();
        _enable = new std::atomic<int32_t>(0);
        _level = new std::atomic<int32_t>(0);
        _output = new FakeOutput(_log);
        _keyer = new FakeKeyer(_log, _enable, _level);
    }
    return self;
}
- (void)dealloc {
    if (_output) _output->Release();
    if (_keyer) _keyer->Release();
    delete _enable;
    delete _level;
}
- (int32_t)setLevelResult { return _level->load(); }
- (void)setSetLevelResult:(int32_t)v { _level->store(v); }
- (int32_t)keyerEnableResult { return _enable->load(); }
- (void)setKeyerEnableResult:(int32_t)v { _enable->store(v); }
- (NSArray<NSString*>*)calls { return _log->snapshot(); }
- (void*)rawOutput { return static_cast<IDeckLinkOutput*>(_output); }
- (void*)rawKeyer { return static_cast<IDeckLinkKeyer*>(_keyer); }
@end

@implementation DLBFakeDevice {
    std::shared_ptr<DeviceCounters> _c;
    FakeDeckLink* _device;
}
- (instancetype)init {
    self = [super init];
    if (self) {
        _c = std::make_shared<DeviceCounters>();
        _device = new FakeDeckLink(_c);
    }
    return self;
}
- (instancetype)initWithModelName:(NSString*)modelName subDeviceIndex:(int64_t)subDeviceIndex activeProfile:(uint32_t)activeProfile {
    self = [super init];
    if (self) {
        _c = std::make_shared<DeviceCounters>();
        DeviceFacts facts;
        facts.model = std::string(modelName.UTF8String);
        facts.subDeviceIndex = subDeviceIndex;
        facts.activeProfile = activeProfile;
        _device = new FakeDeckLink(_c, facts);
    }
    return self;
}
- (void)dealloc { if (_device) _device->Release(); }
- (void)sendProfileActivated {
    IDeckLinkProfileCallback* cb = nullptr;
    {
        std::lock_guard<std::mutex> l(_c->mutex);
        cb = _c->callback;
        if (cb) cb->AddRef();
    }
    if (!cb) return;
    FakeProfile* profile = new FakeProfile();
    gInsideProfileCallback = true;
    cb->ProfileActivated(profile);
    gInsideProfileCallback = false;
    profile->Release();
    cb->Release();
}
- (NSInteger)getProfilesCalls { return _c->getProfiles.load(); }
- (NSInteger)getProfilesCallsInsideCallback { return _c->getProfilesInside.load(); }
- (BOOL)callbackInstalled { std::lock_guard<std::mutex> l(_c->mutex); return _c->callback != nullptr; }
- (void*)rawInterface { return static_cast<IDeckLink*>(_device); }
@end
