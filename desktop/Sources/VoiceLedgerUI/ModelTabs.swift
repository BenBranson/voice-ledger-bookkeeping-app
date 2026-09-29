import SwiftUI
import DesignSystem

/// One AI panel at a time with a model picker, instead of a stacked panel
/// per model (owner request 2026-09-29).
struct ModelTabs<Content: View>: View {
    let labels: [String]
    @ViewBuilder let content: (String) -> Content
    @State private var selection = 0

    var body: some View {
        VStack(alignment: .leading, spacing: VLSpacing.xs) {
            if labels.count > 1 {
                Picker("Model", selection: $selection) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { offset, label in
                        Text(label).tag(offset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            content(labels[min(selection, labels.count - 1)])
        }
    }
}
