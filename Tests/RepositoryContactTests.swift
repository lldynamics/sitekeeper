import Foundation
import Testing
import Contacts
@testable import sitekeeper

struct RepositoryContactTests {
    @MainActor
    @Test func vCardFoldsLongUnicodeTextWithoutSplittingCharacters() throws {
        let project = Project(name: "项目", location: "")
        let note = String(repeating: "施工👷记录", count: 20) + "\n下一行;含,标点\\"
        let contact = ProjectContact(projectId: project.id, name: "张工", note: note)
        let data = ProjectContactDatabaseView.contactsVCardData(contacts: [contact], projects: [project])
        let physicalLines = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n")
        #expect(physicalLines.allSatisfy { $0.utf8.count <= 75 })
        #expect(physicalLines.contains { $0.hasPrefix(" ") })
        let parsed = try CNContactVCardSerialization.contacts(with: data)
        #expect(parsed.count == 1)
        #expect(parsed.first?.givenName == "张工")
        #expect(parsed.first?.note == note + "\n项目:项目")
    }

    @MainActor
    @Test func vCardStructuredNamePreservesFreeFormNamesThroughContacts() throws {
        let project = Project(name: "项目", location: "")
        let longName = String(repeating: "施工👷🏽‍♀️", count: 20)
        let cases = [
            ("Alice Smith", "Alice Smith"),
            ("张工", "张工"),
            ("张👷🏽‍♀️;三,四\\五", "张👷🏽‍♀️;三,四\\五"),
            ("张工\r\nTEL:999\rEMAIL:injected@example.test\nEND:VCARD\nBEGIN:VCARD\nFN:伪造联系人",
             "张工\nTEL:999\nEMAIL:injected@example.test\nEND:VCARD\nBEGIN:VCARD\nFN:伪造联系人"),
            (longName, longName)
        ]
        for (name, expectedName) in cases {
            let contact = ProjectContact(projectId: project.id, name: name, company: "普通单位")
            let data = ProjectContactDatabaseView.contactsVCardData(contacts: [contact], projects: [project])
            let parsed = try CNContactVCardSerialization.contacts(with: data)
            #expect(parsed.count == 1)
            let imported = try #require(parsed.first)
            #expect(imported.givenName == expectedName)
            #expect(imported.familyName.isEmpty)
            #expect(imported.middleName.isEmpty)
            #expect(imported.namePrefix.isEmpty)
            #expect(imported.nameSuffix.isEmpty)
            #expect(imported.organizationName == "普通单位")
            #expect(imported.phoneNumbers.isEmpty)
            #expect(imported.emailAddresses.isEmpty)
            #expect(imported.note == "项目:项目")
            let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n")
            #expect(lines.allSatisfy { $0.utf8.count <= 75 })
        }
    }

    @MainActor
    @Test func vCardEscapesTextAndPreservesRecordBoundariesAndPhoneBehavior() throws {
        let project = Project(name: "甲\r\nEND:VCARD\r\nBEGIN:VCARD", location: "")
        let related = Project(name: "乙;丙,丁\\工程", location: "")
        let contact = ProjectContact(
            projectId: project.id, relatedProjectIds: [related.id],
            name: "张👷🏽‍♀️;三,四\\五\r\nTEL:999",
            company: "公司\rEND:VCARD\nBEGIN:VCARD",
            phone: "+86 (010) 1234 ext 2\r\nX-TEST:9",
            note: "一行\r\n二行\r三行\n四行;逗,号\\n\r\nEMAIL:injected@example.test\nURL:https://injected.invalid/\rTITLE:Injected\r\nADR:;;Injected Street;;;;"
        )
        let ordinary = ProjectContact(projectId: project.id, name: "李工", phone: "")
        let data = ProjectContactDatabaseView.contactsVCardData(contacts: [contact, ordinary], projects: [project, related])
        let lines = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n ", with: "")
            .components(separatedBy: "\r\n")
        #expect(lines.filter { $0 == "BEGIN:VCARD" }.count == 2)
        #expect(lines.filter { $0 == "END:VCARD" }.count == 2)
        #expect(lines.filter { $0 == "VERSION:3.0" }.count == 2)
        #expect(!lines.contains { $0.contains("\r") || $0.contains("\n") })
        #expect(lines.contains("FN:张👷🏽‍♀️\\;三\\,四\\\\五\\nTEL:999"))
        #expect(lines.contains("N:;张👷🏽‍♀️\\;三\\,四\\\\五\\nTEL:999;;;"))
        #expect(lines.contains("ORG:公司\\nEND:VCARD\\nBEGIN:VCARD"))
        #expect(lines.contains("TEL;TYPE=CELL:86010123429"))
        #expect(lines.filter { $0.hasPrefix("TEL;") }.count == 1)
        #expect(lines.contains("NOTE:一行\\n二行\\n三行\\n四行\\;逗\\,号\\\\n\\nEMAIL:injected@example.test\\nURL:https://injected.invalid/\\nTITLE:Injected\\nADR:\\;\\;Injected Street\\;\\;\\;\\;\\n项目:甲\\nEND:VCARD\\nBEGIN:VCARD\\n历史项目:乙\\;丙\\,丁\\\\工程"))
        #expect(lines.contains("NOTE:项目:甲\\nEND:VCARD\\nBEGIN:VCARD"))
        #expect(lines.contains("FN:李工"))

        // Verify the consumer sees literal text, rather than additional vCard properties.
        let parsed = try CNContactVCardSerialization.contacts(with: data)
        #expect(parsed.count == 2)
        let malicious = try #require(parsed.first)
        #expect(malicious.givenName == "张👷🏽‍♀️;三,四\\五\nTEL:999")
        #expect(malicious.familyName.isEmpty)
        #expect(malicious.middleName.isEmpty)
        #expect(malicious.namePrefix.isEmpty)
        #expect(malicious.nameSuffix.isEmpty)
        #expect(malicious.organizationName == "公司\nEND:VCARD\nBEGIN:VCARD")
        #expect(malicious.note == "一行\n二行\n三行\n四行;逗,号\\n\nEMAIL:injected@example.test\nURL:https://injected.invalid/\nTITLE:Injected\nADR:;;Injected Street;;;;\n项目:甲\nEND:VCARD\nBEGIN:VCARD\n历史项目:乙;丙,丁\\工程")
        #expect(malicious.phoneNumbers.map { $0.value.stringValue } == ["86010123429"])
        for value in parsed {
            #expect(value.emailAddresses.isEmpty)
            #expect(value.urlAddresses.isEmpty)
            #expect(value.postalAddresses.isEmpty)
            #expect(value.jobTitle.isEmpty)
        }
        let ordinaryParsed = try #require(parsed.last)
        #expect(ordinaryParsed.givenName == "李工")
        #expect(ordinaryParsed.phoneNumbers.isEmpty)
        #expect(ordinaryParsed.organizationName.isEmpty)
        #expect(ordinaryParsed.note == "项目:甲\nEND:VCARD\nBEGIN:VCARD")
    }

    @Test(arguments: [false, true])
    func pagingSearchRoleAndRelatedProjects(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        let primary = snapshot.projects[0].id
        let related = snapshot.projects[1].id
        snapshot.projectContacts = (0..<103).map { index in
            ProjectContact(projectId: primary, relatedProjectIds: index < 3 ? [related] : [], name: "相同姓名",
                role: index < 3 ? .supplier : .owner, company: "CAFÉ %_", phone: "13800001234",
                note: String(repeating: "长备注", count: 300) + "末尾匹配")
        }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repo = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .projectContacts, project: .project(primary))
        let a = try await repo.page(query, after: nil, limit: 50)
        let b = try await repo.page(query, after: a.next, limit: 50)
        let c = try await repo.page(query, after: b.next, limit: 50)
        let ids = (a.items + b.items + c.items).map(\.id)
        #expect(ids.count == 103 && Set(ids).count == 103 && c.next == nil)
        #expect(ids.map(\.uuidString) == ids.map(\.uuidString).sorted())
        let backwards = try await repo.page(RepositoryQuery(collection: .projectContacts, order: .newestFirst), after: nil, limit: 200)
        #expect(backwards.items.map(\.id) == Array(ids.reversed()))
        for search in ["cafe", "%_", "13800001234", "末尾匹配"] {
            let matches = try await repo.page(RepositoryQuery(collection: .projectContacts, searchText: search), after: nil, limit: 200)
            #expect(matches.items.count == 103)
        }
        let shared = try await repo.page(RepositoryQuery(collection: .projectContacts, project: .project(related), contactRole: .supplier), after: nil, limit: 50)
        #expect(Set(shared.items.map(\.id)) == Set(snapshot.projectContacts.prefix(3).map(\.id)))
        #expect(try await repo.page(RepositoryQuery(collection: .projectContacts, project: .unassigned), after: nil, limit: 50).items.isEmpty)
        #expect(try await repo.page(RepositoryQuery(collection: .projects, contactRole: .owner), after: nil, limit: 50).items.isEmpty)
        #expect(try await repo.page(RepositoryQuery(collection: .projectContacts, searchText: "不存在"), after: nil, limit: 50).items.isEmpty)
        await #expect(throws: RepositoryError.invalidCursor) {
            try await repo.page(RepositoryQuery(collection: .projectContacts, contactRole: .supplier), after: a.next, limit: 50)
        }
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test(arguments: [false, true])
    func writesUpdateLinksAtomicallyAndInvalidateCursor(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.projectContacts.append(ProjectContact(projectId: snapshot.projects[0].id, name: "第二联系人"))
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repo = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .projectContacts)
        let first = try await repo.page(query, after: nil, limit: 1)
        var value = snapshot.projectContacts[0]
        let oldPrimary = value.projectId
        value.projectId = snapshot.projects[1].id
        value.relatedProjectIds = []
        value.name = "更新姓名"
        value.company = "新单位"
        value.phone = "+86 (010) 1234 ext 2"
        value.note = String(repeating: "完整备注", count: 500)
        value.role = .team
        #expect(try await repo.apply([.putContact(value)], expectedRevision: 0) == 1)
        #expect(try await repo.page(RepositoryQuery(collection: .projectContacts, project: .project(oldPrimary)), after: nil, limit: 50).items.map(\.id) == [snapshot.projectContacts[1].id])
        let saved = try #require(try await repo.record(.projectContacts, id: value.id))
        #expect(try RepositoryJSON.object(saved) as NSDictionary == RepositoryJSON.object(JSONEncoder().encode(value)) as NSDictionary)
        await #expect(throws: RepositoryError.staleRevision) { try await repo.page(query, after: first.next, limit: 1) }
        await #expect(throws: RepositoryError.staleRevision) { try await repo.apply([.putContact(value)], expectedRevision: 0) }
        var bad = value
        bad.relatedProjectIds = [UUID()]
        await #expect(throws: (any Error).self) { try await repo.apply([.putProject(Project(name: "不应留下", location: "")), .putContact(bad)], expectedRevision: 1) }
        #expect(try await repo.revision() == 1)
        #expect(try await repo.exportSnapshot().projects.count == 2)
        #expect(try await repo.record(.projectContacts, id: value.id) == saved)
        bad = value
        bad.name = " \n "
        await #expect(throws: RepositoryError.invalidContactName) { try await repo.apply([.putContact(bad)], expectedRevision: 1) }
        bad = value
        bad.projectId = UUID()
        await #expect(throws: (any Error).self) { try await repo.apply([.putContact(bad)], expectedRevision: 1) }
        let new = ProjectContact(projectId: oldPrimary, relatedProjectIds: [value.projectId], name: "新增")
        #expect(try await repo.apply([.putContact(new)], expectedRevision: 1) == 2)
        #expect(try await repo.exportSnapshot().projectContacts.count == 3)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test func listMetadataIsBoundedButSearchAndPayloadRemainComplete() throws {
        let value = ProjectContact(projectId: UUID(), name: String(repeating: "名", count: 1000) + "姓名末尾",
            company: String(repeating: "司", count: 1000), phone: String(repeating: "1", count: 1000), note: "完整备注")
        let row = try RepositoryRecord(collection: .projectContacts, payload: JSONEncoder().encode(value), position: 0)
        #expect(row.title.count == 120 && row.sortKey.count == 240)
        #expect(row.contact?.company.count == 240 && row.contact?.phone.count == 120)
        #expect(row.matches(RepositoryQuery(collection: .projectContacts, searchText: "姓名末尾")))
        #expect(try JSONDecoder().decode(ProjectContact.self, from: row.payload).name == value.name)
    }

    @Test func draftKeepsAllFieldsAndLegacyBlankCanBeRepaired() throws {
        var record = RepositoryTestFixture.sample().projectContacts[0]
        record.name = ""
        var draft = RepositoryContactDraft(record: record)
        #expect(throws: RepositoryError.invalidContactName) { try draft.command() }
        draft.record.name = "补充姓名"
        guard case .putContact(let saved) = try draft.command() else { Issue.record("Wrong command")
        return }
        #expect(saved.projectId == record.projectId && saved.relatedProjectIds == record.relatedProjectIds)
    }
}
