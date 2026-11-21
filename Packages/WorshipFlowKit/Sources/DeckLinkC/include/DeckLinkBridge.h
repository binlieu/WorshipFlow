// HW-003: public Objective-C interface of the DeckLink bridge. No C++ and no vendor types appear here.
//
// Status: Implemented, Not Verified. This bridge was written against the SDK 16.0 headers and has only ever run
// with the Desktop Video driver absent. Nothing in it has touched a real card.
//
// Threading: callbacks (completion, failure, frames, signal, format, discovery) arrive on SDK-private threads,
// one call at a time per object, and never while the bridge holds one of its own locks. A handler may call back into
// the bridge. Handlers must not block for long: on the input side they delay the next frame.
//
// Every object here is safe to use from any thread; the classes are annotated Sendable because their mutable state is
// guarded internally.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Errors

FOUNDATION_EXPORT NSErrorDomain const DLBErrorDomain;
/// NSError userInfo key holding the SDK's HRESULT as an NSNumber, when one was involved.
FOUNDATION_EXPORT NSErrorUserInfoKey const DLBErrorHRESULTKey;

typedef NS_ERROR_ENUM(DLBErrorDomain, DLBErrorCode) {
    /// The Blackmagic Desktop Video driver is not installed (or not loadable).
    DLBErrorDriverNotInstalled = 1,
    /// The device was removed after this object was created.
    DLBErrorDeviceRemoved = 2,
    /// The mode, pixel format, keying or interface is not supported by this device in its current profile.
    DLBErrorNotSupported = 3,
    /// The hardware is in use by another application or another port (the SDK's E_ACCESSDENIED).
    DLBErrorBusy = 4,
    /// Called in the wrong state: not enabled, already enabled, or already closed.
    DLBErrorBadState = 5,
    DLBErrorBadArgument = 6,
    /// The frame pool is exhausted or a buffer could not be allocated.
    DLBErrorOutOfMemory = 7,
    /// Any other SDK failure; see DLBErrorHRESULTKey and the localized description.
    DLBErrorSDKFailure = 8,
    /// A profile change did not complete in time.
    DLBErrorProfileTimeout = 9,
} NS_SWIFT_NAME(DLBError);

// MARK: - Plain data

/// How the SDK reported the fate of one scheduled frame.
typedef NS_ENUM(NSInteger, DLBCompletionResult) {
    DLBCompletionResultCompleted = 0,
    DLBCompletionResultDisplayedLate = 1,
    DLBCompletionResultDropped = 2,
    DLBCompletionResultFlushed = 3,
    /// A value the bridge did not recognise. Treat as not shown.
    DLBCompletionResultUnknown = 4,
} NS_SWIFT_NAME(DLBCompletionResult);

/// Whether the BGRA colour in the supplied buffer is already multiplied by alpha.
typedef NS_ENUM(NSInteger, DLBAlphaMode) {
    DLBAlphaModePremultiplied = 0,
    /// The supplied buffer is premultiplied; the bridge divides colour by alpha while copying, so the card
    /// receives straight (unassociated) colour.
    DLBAlphaModeStraight = 1,
} NS_SWIFT_NAME(DLBAlphaMode);

/// Copies a BGRA image, top row first, into a destination that may have a different row stride, optionally
/// un-premultiplying. Destination padding bytes (the part of each destination row past width*4) are not touched.
/// Returns NO, and writes nothing, when a pointer is null, a dimension is zero, or either stride is smaller than
/// width*4. The two buffers must not overlap. This is the one copy the bridge makes into an SDK frame buffer; it is
/// public so it can be tested without a card.
FOUNDATION_EXPORT BOOL DLBPackBGRA(const uint8_t * _Nullable source, size_t sourceRowBytes,
                                   size_t width, size_t height,
                                   uint8_t * _Nullable destination, size_t destinationRowBytes,
                                   DLBAlphaMode alphaMode);

/// Whether the Desktop Video driver is present, and which API version it reports.
NS_SWIFT_SENDABLE
@interface DLBDriverInfo : NSObject
@property (nonatomic, readonly) BOOL present;
/// For example "16.0", straight from the driver; nil when absent or not reported.
@property (nonatomic, readonly, copy, nullable) NSString *apiVersionString;
/// The driver's raw version integer (0x10000000 is 16.0), or 0 when absent.
@property (nonatomic, readonly) int64_t apiVersionRaw;
/// The version of the headers this bridge was compiled against, for example "16.0".
@property (class, nonatomic, readonly, copy) NSString *compiledAPIVersionString;
/// Queries the driver now. Never throws and never crashes when the driver is missing. Note that the SDK loads its
/// framework once per process: a driver installed while the app is running is not noticed until the app restarts.
+ (DLBDriverInfo *)current;
- (instancetype)init NS_UNAVAILABLE;
@end

/// One profile a device offers. Attributes are read from the profile itself, so they describe what the device would
/// do if that profile were active, without activating it.
NS_SWIFT_SENDABLE
@interface DLBProfileInfo : NSObject
/// A BMDProfileID four-character code, for example '1dfd'.
@property (nonatomic, readonly) uint32_t profileID;
@property (nonatomic, readonly, copy) NSString *profileIDString;
@property (nonatomic, readonly) BOOL isActive;
@property (nonatomic, readonly) BOOL supportsExternalKeying;
@property (nonatomic, readonly) BOOL supportsInternalKeying;
@property (nonatomic, readonly) BOOL supportsPlayback;
@property (nonatomic, readonly) BOOL supportsCapture;
/// A BMDDuplexMode four-character code under this profile, or 0 if the SDK did not say.
@property (nonatomic, readonly) uint32_t duplexMode;
@property (nonatomic, readonly, copy) NSString *duplexModeString;
/// BMDDeckLinkNumberOfSubDevices under this profile, or -1 if not reported.
@property (nonatomic, readonly) int64_t numberOfSubDevices;
- (instancetype)init NS_UNAVAILABLE;
@end

/// Everything the bridge can read about one DeckLink device (one sub-device of a card). An immutable snapshot:
/// ask the device to refresh it after a profile change.
NS_SWIFT_SENDABLE
@interface DLBDeviceInfo : NSObject
@property (nonatomic, readonly, copy) NSString *modelName;
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly) BOOL hasPersistentID;
@property (nonatomic, readonly) int64_t persistentID;
@property (nonatomic, readonly) BOOL hasDeviceGroupID;
@property (nonatomic, readonly) int64_t deviceGroupID;
@property (nonatomic, readonly) BOOL hasTopologicalID;
@property (nonatomic, readonly) int64_t topologicalID;
/// Sub-device index within the card, or -1 if the SDK did not report one.
@property (nonatomic, readonly) int64_t subDeviceIndex;
/// BMDDeckLinkNumberOfSubDevices under the active profile, or -1.
@property (nonatomic, readonly) int64_t numberOfSubDevices;
@property (nonatomic, readonly) BOOL supportsPlayback;
@property (nonatomic, readonly) BOOL supportsCapture;
@property (nonatomic, readonly) BOOL supportsInternalKeying;
@property (nonatomic, readonly) BOOL supportsExternalKeying;
@property (nonatomic, readonly) BOOL supportsInputFormatDetection;
/// BMDVideoConnection bit field for output and for input. 1 is SDI.
@property (nonatomic, readonly) uint32_t videoOutputConnections;
@property (nonatomic, readonly) uint32_t videoInputConnections;
/// BMDDuplexMode four-character code of this sub-device under the active profile; 0 if not reported.
@property (nonatomic, readonly) uint32_t duplexMode;
@property (nonatomic, readonly, copy) NSString *duplexModeString;
/// Whether the device has no IDeckLinkProfileManager, so exactly one profile exists.
@property (nonatomic, readonly) BOOL hasSingleProfile;
@property (nonatomic, readonly) BOOL hasActiveProfile;
@property (nonatomic, readonly) uint32_t activeProfileID;
@property (nonatomic, readonly, copy) NSString *activeProfileIDString;
@property (nonatomic, readonly, copy) NSArray<DLBProfileInfo *> *profiles;
/// BMDDeckLinkMinimumPrerollFrames, or -1 if not reported.
@property (nonatomic, readonly) int64_t minimumPrerollFrames;
/// Whether an IDeckLinkOutput / IDeckLinkInput / IDeckLinkKeyer could be obtained from the device.
@property (nonatomic, readonly) BOOL hasOutputInterface;
@property (nonatomic, readonly) BOOL hasInputInterface;
@property (nonatomic, readonly) BOOL hasKeyerInterface;
/// BMDDeviceInterface four-character code (PCI, USB, Thunderbolt), or 0.
@property (nonatomic, readonly) uint32_t deviceInterface;
@property (nonatomic, readonly, copy) NSString *deviceInterfaceString;
/// All of the above as plain values (NSString, NSNumber, NSArray, NSDictionary), for diagnostics.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *snapshot;
- (instancetype)init NS_UNAVAILABLE;
@end

// MARK: - Output

typedef void (^DLBFrameCompletionHandler)(int64_t frameIndex, DLBCompletionResult result) NS_SWIFT_SENDABLE;
typedef void (^DLBFailureHandler)(NSError *error) NS_SWIFT_SENDABLE;
typedef void (^DLBProfileChangeHandler)(void) NS_SWIFT_SENDABLE;

/// One video output on one sub-device: scheduled playback of BGRA frames, optionally with the external keyer.
///
/// Sequence: supportsDisplayMode -> enable -> scheduleFrame x preroll -> startPlayback -> (scheduleFrame from the
/// completion handler) -> stopPlayback -> disable -> close.
NS_SWIFT_SENDABLE
@interface DLBOutput : NSObject
/// Whether the device can play this mode as BGRA, with the keyer when `keying` is set. `displayMode` is a
/// BMDDisplayMode four-character code. When the SDK substitutes another mode the substitute is returned in
/// `actualMode`.
- (BOOL)supportsDisplayMode:(uint32_t)displayMode keying:(BOOL)keying actualMode:(uint32_t * _Nullable)actualMode;
/// Enables the output. The bridge reads the SDK's own width, height and frame duration for `displayMode` and fails
/// with DLBErrorNotSupported if they differ from the expected values, so a 59.94/60 mix-up cannot slip through.
/// With `keying` the external keyer is enabled at `keyerLevel` (255 is full).
- (BOOL)enableDisplayMode:(uint32_t)displayMode
                    width:(int32_t)width height:(int32_t)height
            frameDuration:(int64_t)frameDuration timeScale:(int64_t)timeScale
                   keying:(BOOL)keying keyerLevel:(uint8_t)keyerLevel
                    error:(NSError **)error;
/// Copies `bgra` (premultiplied, top row first, `width*height*4` bytes with no row padding) once into a pooled SDK frame
/// and schedules it for display at frame `frameIndex` (display time = index * frameDuration).
- (BOOL)scheduleBGRA:(const uint8_t *)bgra byteCount:(size_t)byteCount
          frameIndex:(int64_t)frameIndex alphaMode:(DLBAlphaMode)alphaMode
               error:(NSError **)error;
/// Starts scheduled playback at `frameIndex`. Call after the preroll frames are scheduled.
- (BOOL)startPlaybackAtFrame:(int64_t)frameIndex error:(NSError **)error;
/// Stops playback immediately; frames still queued are reported to the completion handler as flushed.
- (void)stopPlayback;
- (BOOL)setKeyerLevel:(uint8_t)level error:(NSError **)error;
/// Stops playback if needed, turns the keyer off, disables the output and frees the frame pool. Safe to repeat.
- (void)disable;
/// Disables and releases the device interfaces; the object is unusable afterwards. Safe to repeat.
- (void)close;
@property (nonatomic, readonly) BOOL isEnabled;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) BOOL isClosed;
/// The device's BMDDeckLinkMinimumPrerollFrames as read when the output was opened, or -1 if the device did not report it.
@property (nonatomic, readonly) int64_t minimumPrerollFrames;
/// Frames scheduled but not yet completed, according to the SDK; 0 when not enabled.
@property (nonatomic, readonly) uint32_t bufferedFrameCount;
/// Set before `enable`. Called once per scheduled frame.
@property (atomic, copy, nullable) DLBFrameCompletionHandler completionHandler;
/// Called when the device disappears or the SDK reports a fatal condition under this output.
@property (atomic, copy, nullable) DLBFailureHandler failureHandler;
/// Plain-value diagnostics: state, mode, keyer, counters, reference lock, pool size.
- (NSDictionary<NSString *, id> *)statusSnapshot;
- (instancetype)init NS_UNAVAILABLE;
@end

// MARK: - Input

/// What the input saw on its connector.
typedef void (^DLBInputFrameHandler)(const uint8_t *bgra, size_t byteCount, int32_t width, int32_t height, size_t rowBytes,
                                     int64_t hardwareTimestampNanoseconds) NS_SWIFT_SENDABLE;
/// `hasSignal` is NO when the SDK flags frames as having no input source. Called on every change, not every frame.
typedef void (^DLBSignalHandler)(BOOL hasSignal) NS_SWIFT_SENDABLE;
/// A format was detected or changed. `displayMode` is a BMDDisplayMode code; `frameDuration`/`timeScale` are the SDK's.
typedef void (^DLBInputFormatHandler)(uint32_t displayMode, int32_t width, int32_t height,
                                      int64_t frameDuration, int64_t timeScale, BOOL interlaced) NS_SWIFT_SENDABLE;

/// One video input on one sub-device. Frames are delivered as BGRA bytes; the pointer is valid only during the call.
NS_SWIFT_SENDABLE
@interface DLBInput : NSObject
/// Whether the device can capture this mode (a BMDDisplayMode code) on this connector, as 8-bit YCbCr.
- (BOOL)supportsDisplayMode:(uint32_t)displayMode;
/// Starts capture with automatic format detection when the device supports it. `initialDisplayMode` is the mode
/// assumed until a signal is detected (a BMDDisplayMode code).
- (BOOL)startWithInitialDisplayMode:(uint32_t)initialDisplayMode
                    detectFormat:(BOOL)detectFormat
                           error:(NSError **)error;
- (void)stop;
- (void)close;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) BOOL isClosed;
@property (atomic, copy, nullable) DLBInputFrameHandler frameHandler;
@property (atomic, copy, nullable) DLBSignalHandler signalHandler;
@property (atomic, copy, nullable) DLBInputFormatHandler formatHandler;
@property (atomic, copy, nullable) DLBFailureHandler failureHandler;
- (NSDictionary<NSString *, id> *)statusSnapshot;
- (instancetype)init NS_UNAVAILABLE;
@end

// MARK: - Device and discovery

/// One IDeckLink: a card, or one sub-device of a multi-sub-device card such as the DeckLink Duo 2.
NS_SWIFT_SENDABLE
@interface DLBDevice : NSObject
/// The latest snapshot. Replaced by `refreshInfo` and after a profile change.
@property (atomic, readonly, strong) DLBDeviceInfo *info;
/// NO once the SDK has reported the device removed.
@property (nonatomic, readonly) BOOL isPresent;
/// Re-reads every attribute and returns the new snapshot.
- (DLBDeviceInfo *)refreshInfo;
/// Activates a profile (a BMDProfileID code) and waits up to `timeout` seconds for the SDK to report it active.
/// The SDK applies the change to every sub-device that shares the profile; running streams on them may stop.
/// Returns YES also when the profile was already active.
- (BOOL)activateProfile:(uint32_t)profileID timeout:(NSTimeInterval)timeout error:(NSError **)error;
/// Tells the device it is gone, so every open output and input reports a removal. Discovery does this for the
/// devices it created; a caller that learned of a removal another way (a re-scan) calls it for its own objects.
- (void)markRemoved;
- (nullable DLBOutput *)openOutputWithError:(NSError **)error;
- (nullable DLBInput *)openInputWithError:(NSError **)error;
/// Called after a profile change completes on this device (from an SDK thread).
@property (atomic, copy, nullable) DLBProfileChangeHandler profileChangeHandler;
- (NSDictionary<NSString *, id> *)statusSnapshot;
- (instancetype)init NS_UNAVAILABLE;
@end

/// Reports DeckLink devices arriving and leaving. The SDK reports every device already connected right after `start`.
NS_SWIFT_SENDABLE
@interface DLBDiscovery : NSObject
- (instancetype)initWithArrived:(void (^)(DLBDevice *device))arrived
                        removed:(void (^)(DLBDevice *device))removed NS_SWIFT_NAME(init(arrived:removed:));
/// Fails with DLBErrorDriverNotInstalled when the driver is absent. Calling it twice is harmless.
- (BOOL)startWithError:(NSError **)error;
- (void)stop;
/// Devices currently known to this discovery object (arrived and not yet removed).
@property (nonatomic, readonly, copy) NSArray<DLBDevice *> *devices;
- (instancetype)init NS_UNAVAILABLE;
@end

/// Entry points that need no object.
NS_SWIFT_SENDABLE
@interface DLBBridge : NSObject
/// Synchronously lists the DeckLink devices (IDeckLinkIterator). Empty when the driver is absent or no card is present.
+ (NSArray<DLBDevice *> *)enumerateDevices;
/// The driver and every device, one dictionary of plain values, for the diagnostics screen.
+ (NSDictionary<NSString *, id> *)statusSnapshot;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
