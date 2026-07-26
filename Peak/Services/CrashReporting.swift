import Foundation
import Sentry

/// Crash, hang and handled-error reporting.
///
/// Wrapped so call sites never touch the SDK directly, and so every privacy
/// decision lives in one place. No-ops entirely when `SENTRY_DSN` is unset —
/// nothing is initialised and no network calls are made.
///
/// Both of today's worst bugs would have surfaced here immediately: the
/// WalletConnect launch crash (which presented as a freeze) and the
/// EventDetailView main-thread hang.
enum CrashReporting {
    static func start() {
        guard SentryConfig.isConfigured else { return }
        SentrySDK.start { options in
            options.dsn = SentryConfig.dsn

            #if DEBUG
            options.environment = "debug"
            // Don't ship noise from development builds.
            options.enabled = false
            #else
            options.environment = "release"
            #endif

            // This app handles wallets and money. Users' addresses, balances and
            // order sizes travel through error messages already; do not let the
            // SDK attach IP addresses, usernames or device identifiers on top.
            options.sendDefaultPii = false

            // Screens can show balances, positions and market questions.
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // The hang detector is the point of this integration as much as
            // crashes are — a wedged main thread is invisible otherwise.
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2

            // Enough tracing to spot slow paths without sampling every order.
            options.tracesSampleRate = 0.1
        }
    }

    /// Record a handled error with light context, e.g. ["path": "orders"].
    ///
    /// Pass identifiers and outcomes, never amounts, addresses or keys.
    static func capture(_ error: Error, context: [String: String] = [:]) {
        guard SentryConfig.isConfigured else { return }
        SentrySDK.capture(error: error) { scope in
            for (key, value) in context {
                scope.setTag(value: value, key: key)
            }
        }
    }

    /// Trail of what led to a later failure. Reports nothing on its own.
    static func breadcrumb(_ message: String, category: String) {
        guard SentryConfig.isConfigured else { return }
        let crumb = Breadcrumb(level: .info, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }
}
