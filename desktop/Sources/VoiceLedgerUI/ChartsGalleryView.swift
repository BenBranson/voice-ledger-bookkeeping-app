import SwiftUI
import Core
import Voice
import DesignSystem

/// Charts & Cards: every card Moneypenny can show, as a clickable list that
/// says what each one shows and the words to say for it.
public struct ChartsGalleryView: View {
    let environment: VLEnvironmentTone
    let onRun: (String) -> Void
    @State private var vendorName = ""
    @State private var accountName = ""

    public init(environment: VLEnvironmentTone, onRun: @escaping (String) -> Void) {
        self.environment = environment
        self.onRun = onRun
    }

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: VLSpacing.md)]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.lg) {
                HStack {
                    Text("Charts & Cards").font(VLTypography.pageTitle()).foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(environment)
                }
                Text("Click any card to pop it up for the client you're in. Each shows the same figures as its page, with QuickBooks links and what to do. You can also say the words in quotes to Moneypenny.")
                    .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).fixedSize(horizontal: false, vertical: true)

                ForEach(CardCatalog.sections) { section in
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        Text(section.title.uppercased()).font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(VLColor.cyan)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: VLSpacing.md) {
                            ForEach(section.items) { item in tile(item) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: VLSpacing.sm) {
                    Text("ONE VENDOR, CUSTOMER OR ACCOUNT").font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(VLColor.cyan)
                    VLCard {
                        VStack(alignment: .leading, spacing: VLSpacing.sm) {
                            HStack {
                                TextField("Vendor or customer name (e.g. Hicks Hardware)", text: $vendorName).textFieldStyle(.roundedBorder).onSubmit(runVendor)
                                Button("Show card", action: runVendor).disabled(vendorName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            Text("12 months of spending or invoicing by month, recent transactions with QuickBooks links, and any price jump or same-day double charge. Say “find” and the name.")
                                .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                            Divider().overlay(VLColor.border)
                            HStack {
                                TextField("Account name (e.g. Checking, Mastercard)", text: $accountName).textFieldStyle(.roundedBorder).onSubmit(runAccount)
                                Button("Show card", action: runAccount).disabled(accountName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            Text("Current balance read the way the Balance Sheet does, latest postings with links, and whether the balance looks right. Say “balance of” and the name.")
                                .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                        }
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private func runVendor() { let n = vendorName.trimmingCharacters(in: .whitespaces); if !n.isEmpty { onRun(CardCatalog.vendorPhrase(n)) } }
    private func runAccount() { let n = accountName.trimmingCharacters(in: .whitespaces); if !n.isEmpty { onRun(CardCatalog.accountPhrase(n)) } }

    private func tile(_ item: CardCatalog.Item) -> some View {
        Button { onRun(item.phrase) } label: {
            VLCard {
                VStack(alignment: .leading, spacing: VLSpacing.xs) {
                    HStack(spacing: VLSpacing.sm) {
                        Image(systemName: item.symbol).font(.system(size: 18)).foregroundStyle(VLColor.cyan).frame(width: 24)
                        Text(item.title).font(VLTypography.cardTitle()).foregroundStyle(VLColor.textPrimary)
                        Spacer()
                        Image(systemName: "rectangle.portrait.on.rectangle.portrait").foregroundStyle(VLColor.textMuted)
                    }
                    Text(item.shows).font(VLTypography.caption()).foregroundStyle(VLColor.textSecondary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text("Say: “\(item.phrase)”").font(VLTypography.caption()).foregroundStyle(VLColor.violet)
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
        .help("Show the \(item.title) card")
    }
}
