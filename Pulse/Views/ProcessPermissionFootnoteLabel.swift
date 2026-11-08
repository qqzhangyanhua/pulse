import SwiftUI

struct ProcessPermissionFootnoteLabel: View {
    let sentence: String?
    let processListFailed: Bool
    let showsProcessTable: Bool

    var body: some View {
        if let text = ProcessPermissionFootnote.visibleSentence(
            sentence,
            processListFailed: processListFailed,
            showsProcessTable: showsProcessTable
        ) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
    }
}
