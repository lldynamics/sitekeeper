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
                row(contact)
            }
            .onDelete { offsets in
                let ids = offsets.compactMap { contacts.indices.contains($0) ? contacts[$0].id : nil }
                onDelete(Set(ids))
            }
        } else {
            ForEach(contacts) { contact in
                row(contact)
            }
        }
    }

    @ViewBuilder
    private func row(_ contact: ProjectContact) -> some View {
        if showsPhoneActions {
            HStack(alignment: .top, spacing: AppSpacing.tight) {
                Button {
                    onSelect(contact)
                } label: {
                    ContactPickerRowView(
                        contact: contact,
                        projectName: projectName(contact.projectId),
                        showsProjectName: showsProjectName,
                        showsPhoneActions: false
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                contactActionLinks(phone: contact.phone)
                    .padding(.top, 4)
            }
        } else {
            Button {
                onSelect(contact)
            } label: {
                ContactPickerRowView(
                    contact: contact,
                    projectName: projectName(contact.projectId),
                    showsProjectName: showsProjectName,
                    showsPhoneActions: false
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func contactActionLinks(phone: String) -> some View {
        let tel = telURL(for: phone)
        let sms = smsURL(for: phone)
        if tel != nil || sms != nil {
            VStack(spacing: AppSpacing.tight) {
                if let tel {
                    Link(destination: tel) {
                        Image(systemName: "phone.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appPrimaryAction)
                    }
                }
                if let sms {
                    Link(destination: sms) {
                        Image(systemName: "message.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appSuccess)
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

struct ContactPickerRowView: View {
    let contact: ProjectContact
    let projectName: String
    var showsProjectName = true
    var showsPhoneActions = true
    var crmSummary: String? = nil
    var linkedProjectNames: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: AppSpacing.tight) {
                Text(contact.name.isEmpty ? "未命名联系人" : contact.name)
                    .font(.body.weight(.semibold))
                Spacer(minLength: AppSpacing.tight)
                Text(contact.roleDisplayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.appDoc)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.appDocSurfaceSubtle)
                    .clipShape(Capsule())
                contactActionLinks(phone: contact.phone)
            }
            if showsProjectName {
                Text(projectName)
                    .font(.caption)
                    .foregroundStyle(Color.appPrimaryAction)
            }
            if !linkedProjectNames.isEmpty {
                Text("🔗 \(linkedProjectNames.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !contact.company.isEmpty || !contact.phone.isEmpty {
                Text([contact.company, contact.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let crmSummary,
               !crmSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(crmSummary)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.appPrimaryAction)
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
            HStack(spacing: AppSpacing.tight) {
                if let tel {
                    Link(destination: tel) {
                        Image(systemName: "phone.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.appSuccess)
                            .frame(width: 24, height: 24)
                            .background(Color.appSuccess.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if let sms {
                    Link(destination: sms) {
                        Image(systemName: "message.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.appPrimaryAction)
                            .frame(width: 24, height: 24)
                            .background(Color.appPrimaryAction.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .buttonStyle(.plain)
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
