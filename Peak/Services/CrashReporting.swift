import Foundation

/// Crash / error reporting hooks.
/// Sentry SPM was removed because Xcode could not reliably resolve the package product;
/// these calls are intentional no-ops so trading / auth paths stay instrumentable later
/// without blocking builds. Wire a real SDK here when package resolution is stable.
enum CrashReporting {
    static func start() {}

    static func capture(_ error: Error, context: [String: String] = [:]) {
        #if DEBUG
        if !context.isEmpty {
            print("[CrashReporting] \(error.localizedDescription) \(context)")
        }
        #endif
    }

    static func breadcrumb(_ message: String, category: String) {
        #if DEBUG
        print("[CrashReporting:\(category)] \(message)")
        #endif
    }
}
