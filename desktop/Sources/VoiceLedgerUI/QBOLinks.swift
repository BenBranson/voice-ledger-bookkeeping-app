import SwiftUI
import Core
import DesignSystem

/// Owner directive 2026-10-02: "a qbo link for practically every
/// transaction", and every link must open the exact record (transaction,
/// account register, vendor or customer), never QBO in general. Injected
/// once at the root so any screen can show a link without plumbing.
/// Navigation only, never a write.
public struct QBOLinks: Sendable, Equatable {
    public var isSandbox: Bool
    /// Finding ID → the exact record behind it (`QBOWebLink.url(for:)`).
    public var findingURLs: [String: URL]
    /// Account ID → its register (balance sheet accounts only).
    public var accountURLs: [String: URL]
    /// Lowercased account name → account ID.
    public var accountIDsByName: [String: String]
    /// Lowercased vendor display name → vendor ID.
    public var vendorIDsByName: [String: String]

    public init(isSandbox: Bool, findingURLs: [String: URL] = [:], accountURLs: [String: URL] = [:], accountIDsByName: [String: String] = [:], vendorIDsByName: [String: String] = [:]) {
        self.isSandbox = isSandbox
        self.findingURLs = findingURLs
        self.accountURLs = accountURLs
        self.accountIDsByName = accountIDsByName
        self.vendorIDsByName = vendorIDsByName
    }

    public static let none = QBOLinks(isSandbox: true)

    public func finding(_ id: String?) -> URL? { id.flatMap { findingURLs[$0] } }
    public func account(id: String?) -> URL? { id.flatMap { accountURLs[$0] } }
    public func account(named name: String) -> URL? { account(id: accountIDsByName[Self.key(name)]) }
    public func vendor(named name: String) -> URL? {
        vendorIDsByName[Self.key(name)].flatMap { QBOWebLink.vendor(id: $0, isSandbox: isSandbox) }
    }
    public func vendor(id: String?) -> URL? { id.flatMap { QBOWebLink.vendor(id: $0, isSandbox: isSandbox) } }
    public func customer(id: String?) -> URL? { id.flatMap { QBOWebLink.customer(id: $0, isSandbox: isSandbox) } }
    public func transaction(id: String?, typeName: String?) -> URL? {
        id.flatMap { QBOWebLink.transaction(id: $0, reportTypeName: typeName, isSandbox: isSandbox) }
    }

    static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespaces).lowercased() }
}

private struct QBOLinksKey: EnvironmentKey { static let defaultValue = QBOLinks.none }

public extension EnvironmentValues {
    var qboLinks: QBOLinks {
        get { self[QBOLinksKey.self] }
        set { self[QBOLinksKey.self] = newValue }
    }
}

/// The standard "Open in QBO" link. Renders nothing when there is no exact
/// record to open, so a row never gets a link to a general page.
public struct QBOLinkButton: View {
    let url: URL?
    let compact: Bool

    public init(_ url: URL?, compact: Bool = false) {
        self.url = url
        self.compact = compact
    }

    public var body: some View {
        if let url {
            Link(destination: url) {
                if compact {
                    Image(systemName: "arrow.up.right.square")
                } else {
                    Label("Open in QBO", systemImage: "arrow.up.right.square")
                }
            }
            .font(VLTypography.caption())
            .help("Open this record in QuickBooks — \(url.absoluteString)")
        }
    }
}
