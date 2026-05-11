import SwiftUI

struct ContactPickerView: View {
    let contacts: [ProjectContact]
    let projectName: (UUID) -> String
    var showsProjectName = true
    var showsPhoneActions = false
    var emptyTitle: String
    var emptySystemImage: String
    var emptyDescription: Text
    let onSelect: (ProjectContact) -> Void
    var onDelete: ((Set<UUID>) -> Void)? = nil

    var body: some View {
        if contacts.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: emptySystemImage,
                description: emptyDescription
            )
        } else if let onDelete {
            ForEach(contacts) { contact in
                Button {
                    onSelect(contact)
                } label: {
                    ContactPickerRowView(
                        contact: contact,
                        projectName: projectName(contact.projectId),
                        showsProjectName: showsProjectName,
                        showsPhoneActions: showsPhoneActions
                    )
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                let ids = offsets.compactMap { contacts.indices.contains($0) ? contacts[$0].id : nil }
                onDelete(Set(ids))
            }
        } else {
            ForEach(contacts) { contact in
                Button {
                    onSelect(contact)
                } label: {
                    ContactPickerRowView(
                        contact: contact,
                        projectName: projectName(contact.projectId),
                        showsProjectName: showsProjectName,
                        showsPhoneActions: showsPhoneActions
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ContactPickerRowView: View {
    let contact: ProjectContact
    let projectName: String
    var showsProjectName = true
    var showsPhoneActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(contact.name.isEmpty ? "未命名联系人" : contact.name)
                    .font(.body.weight(.semibold))
                Spacer(minLength: AppSpacing.tight)
                Text(contact.roleDisplayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.appDocSurfaceSubtle)
                    .clipShape(Capsule())
                if showsPhoneActions {
                    contactActionLinks(phone: contact.phone)
                }
            }
            if showsProjectName {
                Text(projectName)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !contact.company.isEmpty || !contact.phone.isEmpty {
                Text([contact.company, contact.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !contact.note.isEmpty {
                Text(contact.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func contactActionLinks(phone: String) -> some View {
        let tel = telURL(for: phone)
        let sms = smsURL(for: phone)
        if tel != nil || sms != nil {
            HStack(spacing: AppSpacing.normal) {
                if let tel {
                    Link(destination: tel) {
                        Image(systemName: "phone.fill")
                    }
                }
                if let sms {
                    Link(destination: sms) {
                        Image(systemName: "message.fill")
                    }
                }
            }
        }
    }

    private func telURL(for phone: String) -> URL? {
        let cleaned = normalizedPhone(phone)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "tel:\(cleaned)")
    }

    private func smsURL(for phone: String) -> URL? {
        let cleaned = normalizedPhone(phone)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "sms:\(cleaned)")
    }

    private func normalizedPhone(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
    }
}
