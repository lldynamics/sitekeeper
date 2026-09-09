import SwiftUI
import Contacts
import ContactsUI

struct ImportedSystemContact: Sendable {
    let fullName: String
    let organizationName: String
    let phoneNumbers: [String]

    var primaryPhone: String {
        phoneNumbers.first ?? ""
    }

    static func from(contact: CNContact, preferredPhone: String? = nil) -> ImportedSystemContact {
        let fullName = CNContactFormatter.string(from: contact, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let fallbackName = [contact.familyName, contact.middleName, contact.givenName]
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = fullName.isEmpty ? fallbackName : fullName

        let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPreferredPhone = preferredPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phones = contact.phoneNumbers
            .map { $0.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var ordered: [String] = []
        if !trimmedPreferredPhone.isEmpty {
            ordered.append(trimmedPreferredPhone)
        }
        for value in phones where !ordered.contains(value) {
            ordered.append(value)
        }

        return ImportedSystemContact(
            fullName: resolvedName,
            organizationName: organization,
            phoneNumbers: ordered
        )
    }
}

struct SystemContactPicker: UIViewControllerRepresentable {
    let onSelect: (ImportedSystemContact) -> Void
    var onCancel: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForSelectionOfContact = NSPredicate(value: true)
        picker.displayedPropertyKeys = [
            CNContactPhoneNumbersKey,
            CNContactOrganizationNameKey
        ]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let parent: SystemContactPicker

        init(parent: SystemContactPicker) {
            self.parent = parent
        }

        nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let imported = ImportedSystemContact.from(contact: contact)
            Task { @MainActor in self.parent.onSelect(imported) }
        }

        nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            let selectedPhone: String?
            if contactProperty.key == CNContactPhoneNumbersKey,
               let phoneValue = contactProperty.value as? CNPhoneNumber {
                selectedPhone = phoneValue.stringValue
            } else if contactProperty.key == CNContactPhoneNumbersKey,
                      let labeledPhone = contactProperty.value as? CNLabeledValue<CNPhoneNumber> {
                selectedPhone = labeledPhone.value.stringValue
            } else {
                selectedPhone = nil
            }
            let imported = ImportedSystemContact.from(
                contact: contactProperty.contact,
                preferredPhone: selectedPhone
            )
            Task { @MainActor in self.parent.onSelect(imported) }
        }

        nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            Task { @MainActor in self.parent.onCancel?() }
        }
    }
}
