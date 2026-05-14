import SwiftUI

/// Placeholder for the upcoming Customization tab — the live pill preview
/// + accent picker move here from the About tab in a follow-up commit. For
/// now it just renders the page header so the new sidebar can dispatch to
/// it cleanly while the rest of the migration lands.
struct CustomizationTabView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead3(
                title: "Customization",
                subtitle: "Tweak the pill's accent and preview the change live above. The whole app — comet rim, focus glows, badges — retints to match."
            )

            Card3 {
                Text("Pill preview + accent picker land here in the next pass.")
                    .font(CWFont.mono(size: CWFont.s12, weight: .regular))
                    .foregroundColor(.cwFg3)
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
    }
}
