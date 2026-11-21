// HW-004: where the app's SDI cards come from. One real DeckLink provider for the whole process (it owns the driver
// connection and the hot-plug subscription), shared by the screens and the Hardware Test window; the simulated card is
// added beside it only while the developer setting is on. Nothing here has run against a real card.
import DeckLinkSDI
import SDIEngine

enum AppSDI {
    /// The real provider. With no Blackmagic Desktop Video on the Mac it finds nothing, says so, and never raises an error.
    static let deckLink = DeckLinkDeviceProvider()
}
