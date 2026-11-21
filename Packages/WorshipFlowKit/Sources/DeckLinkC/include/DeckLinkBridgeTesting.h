// FIX-C: stand-ins for the SDK's objects, so the bridge's own logic (restart sequences, teardown, keyer, profile callback)
// can be exercised on a Mac with no DeckLink card and no driver. FOR TESTS ONLY: nothing in the app uses this header.
//
// What this proves and what it does not: it proves that the bridge calls the SDK's methods in the order and with the
// arguments it intends and handles the HRESULTs it is given. It proves nothing about how the real SDK behaves.
#import <Foundation/Foundation.h>
#import "DeckLinkBridge.h"

NS_ASSUME_NONNULL_BEGIN

/// A scripted IDeckLinkInput. Every call is recorded; chosen calls can be made to fail.
NS_SWIFT_SENDABLE
@interface DLBFakeInput : NSObject
- (instancetype)init;
/// Whether DoesSupportVideoMode says yes for 8-bit BGRA / 8-bit YCbCr. Both default to YES.
@property (atomic) BOOL bgraSupported;
@property (atomic) BOOL yuvSupported;
/// From now on the named call ("PauseStreams", "EnableVideoInput", "FlushStreams", "StartStreams", "StopStreams",
/// "DisableVideoInput") returns `result` (an HRESULT, for example 0x80004005) instead of S_OK.
- (void)failCall:(NSString *)name withResult:(int32_t)result;
/// The calls so far, in order, for example "PauseStreams", "EnableVideoInput(BGRA)", "SetCallback(set)".
@property (atomic, readonly, copy) NSArray<NSString *> *calls;
- (void)clearCalls;
/// True while the SDK would still hold the bridge's callback object.
@property (atomic, readonly) BOOL callbackInstalled;
/// Does what the SDK does when it detects a new format: calls the installed callback's VideoInputFormatChanged, on the
/// calling thread. Does nothing if no callback is installed.
- (void)sendFormatChange:(uint32_t)displayMode width:(int32_t)width height:(int32_t)height rgb444:(BOOL)rgb444;
/// The IDeckLinkInput this stands for. For `DLBTesting` only.
@property (nonatomic, readonly) void *rawInterface;
@end

/// A scripted IDeckLinkOutput together with its IDeckLinkKeyer.
NS_SWIFT_SENDABLE
@interface DLBFakeOutput : NSObject
- (instancetype)init;
/// The result of IDeckLinkKeyer::SetLevel / ::Enable. Default S_OK.
@property (atomic) int32_t setLevelResult;
@property (atomic) int32_t keyerEnableResult;
@property (atomic, readonly, copy) NSArray<NSString *> *calls;
@property (nonatomic, readonly) void *rawOutput;
@property (nonatomic, readonly) void *rawKeyer;
@end

/// A scripted IDeckLink with a profile manager.
NS_SWIFT_SENDABLE
@interface DLBFakeDevice : NSObject
- (instancetype)init;
/// A sub-device as a card reports it: model name, BMDDeckLinkSubDeviceIndex, and the active BMDProfileID (0: none reported).
- (instancetype)initWithModelName:(NSString *)modelName subDeviceIndex:(int64_t)subDeviceIndex activeProfile:(uint32_t)activeProfile;
/// Does what the SDK does when a profile has been activated: calls ProfileActivated on the installed callback, on the
/// calling thread. While it runs, any profile enumeration the bridge starts on this thread is counted as "inside".
- (void)sendProfileActivated;
/// Times GetProfiles was called, and how many of those calls happened inside `sendProfileActivated` on its thread.
@property (atomic, readonly) NSInteger getProfilesCalls;
@property (atomic, readonly) NSInteger getProfilesCallsInsideCallback;
@property (atomic, readonly) BOOL callbackInstalled;
@property (nonatomic, readonly) void *rawInterface;
@end

/// Builds bridge objects around the stand-ins.
@interface DLBTesting : NSObject
+ (DLBInput *)inputWithFake:(DLBFakeInput *)fake;
+ (DLBOutput *)outputWithFake:(DLBFakeOutput *)fake minimumPrerollFrames:(int64_t)preroll;
+ (DLBDevice *)deviceWithFake:(DLBFakeDevice *)fake;
/// Tells an input its card was removed, as `DLBDevice markRemoved` does.
+ (void)removeInput:(DLBInput *)input;
/// Makes the converter creation succeed with a do-nothing converter (YES) or fail as it does without the driver (NO).
+ (void)setConverterAvailable:(BOOL)available;
/// Input callback objects that exist now. A callback that is never released shows up here as a leak.
+ (NSInteger)liveInputCallbackCount;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
