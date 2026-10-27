import SwiftUI

struct PrivacyPolicyView: View {
    private let policyDocument = AppPolicy.privacyPolicyDocument()

    private var policyTitle: String {
        AppLocalization.string("privacy.policy.title")
    }

    private var lastUpdatedText: String {
        String(
            format: AppLocalization.string("privacy.policy.lastUpdated.format"),
            locale: .current,
            policyDocument.lastUpdatedDisplay
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(policyTitle).font(.title.bold())

                Text(lastUpdatedText)

                Text(policyDocument.body)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(policyTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
