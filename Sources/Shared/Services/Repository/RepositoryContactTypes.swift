import Foundation

struct RepositoryContactFields: Equatable, Sendable {
    let role: ProjectContactRole
    let company: String
    let phone: String

    init(role: ProjectContactRole, company: String, phone: String) {
        self.role = role
        self.company = company
        self.phone = phone
    }

    init(object: [String: Any]) throws {
        guard let project = object["projectId"] as? String, UUID(uuidString: project) != nil else {
            throw RepositoryError.invalidRecord("contact project")
        }
        for key in ["name", "company", "phone", "note", "role"] {
            if let value = object[key], !(value is String) { throw RepositoryError.invalidRecord("contact " + key) }
        }
        if let value = object["relatedProjectIds"] {
            guard let ids = value as? [String], ids.allSatisfy({ UUID(uuidString: $0) != nil }) else {
                throw RepositoryError.invalidRecord("contact related projects")
            }
        }
        guard let role = ProjectContactRole(rawValue: object["role"] as? String ?? ProjectContactRole.owner.rawValue) else {
            throw RepositoryError.invalidRecord("contact role")
        }
        self.init(role: role, company: String((object["company"] as? String ?? "").prefix(240)),
            phone: String((object["phone"] as? String ?? "").prefix(120)))
    }
}

/// Edits retain the original primary and related project IDs. A record can be
/// created from a project page; the all-project page is for browsing/editing.
struct RepositoryContactDraft: Codable, Sendable {
    var record: ProjectContact

    init(record: ProjectContact) { self.record = record }
    init(from decoder: Decoder) throws { self.init(record: try ProjectContact(from: decoder)) }
    func encode(to encoder: Encoder) throws { try record.encode(to: encoder) }

    static func validate(_ value: ProjectContact) throws {
        guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RepositoryError.invalidContactName }
    }

    func command() throws -> RepositoryCommand {
        try Self.validate(record)
        return .putContact(record)
    }
}
