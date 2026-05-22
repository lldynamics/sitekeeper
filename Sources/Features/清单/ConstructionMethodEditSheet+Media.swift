import SwiftUI
import PhotosUI
import UIKit

extension ConstructionMethodEditSheet {
    var basicInfoSection: some View {
        Section(String(localized: "工艺信息")) {
            TextField(String(localized: "标题"), text: $title)
            TextField(String(localized: "专业/工种"), text: $trade)
            TextField(String(localized: "版本号"), text: $versionName)
            Picker(String(localized: "发布状态"), selection: $publishStatus) {
                ForEach(ConstructionMethod.PublishStatus.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
        }
    }

    var tutorialSections: some View {
        ConstructionMethodTutorialEditorSections(
            didRestoreDraft: didRestoreDraft,
            tutorialBody: $tutorialBody,
            selectedTutorialMediaItems: $selectedTutorialMediaItems,
            isImportingTutorialMedia: isImportingTutorialMedia,
            tutorialMediaImportMessage: tutorialMediaImportMessage,
            tutorialAttachments: tutorialAttachments,
            onInsertBlock: appendTutorialBlock,
            onOpenCamera: openTutorialCamera,
            onPreviewAttachment: { previewAttachment = $0 },
            onRemoveAttachment: removeTutorialAttachment
        )
    }

    func appendTutorialBlock(_ block: String) {
        let content = tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            tutorialBody = block
        } else if tutorialBody.hasSuffix("\n") {
            tutorialBody += block
        } else {
            tutorialBody += "\n\(block)"
        }
    }

    func openTutorialCamera() {
        guard ConstructionMethodMediaImportSupport.isCameraAvailable else {
            showError(String(localized: "当前设备不可用相机。"))
            return
        }
        Task { @MainActor in
            guard await ConstructionMethodMediaImportSupport.requestCameraAccessIfNeeded() else {
                showError(String(localized: "未获得相机权限，无法拍摄。"))
                return
            }
            showTutorialCamera = true
        }
    }

    func appendTutorialCameraImageAttachment(_ image: UIImage) {
        do {
            let attachment = try ConstructionMethodMediaImportSupport.makeImageAttachment(from: image)
            tutorialAttachments.append(attachment)
            sessionAddedFileNames.insert(attachment.fileName)
        } catch {
            showError(ConstructionMethodMediaImportSupport.imageSaveFailedMessage(error))
        }
    }

    func removeTutorialAttachment(_ attachment: QuickNoteAttachment) {
        ConstructionMethodMediaImportSupport.removeAttachment(
            attachment,
            from: &tutorialAttachments,
            sessionAddedFileNames: &sessionAddedFileNames,
            summary: "constructionMethodEditor.removeTutorialAttachment"
        )
    }

    func startTutorialMediaImport() {
        isImportingTutorialMedia = true
        tutorialMediaImportMessage = ConstructionMethodMediaImportSupport.importingMessage
    }

    func finishTutorialMediaImport() {
        isImportingTutorialMedia = false
        tutorialMediaImportMessage = ""
        selectedTutorialMediaItems = []
    }

    func importTutorialMediaItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        await MainActor.run {
            startTutorialMediaImport()
        }
        defer {
            Task { @MainActor in
                finishTutorialMediaImport()
            }
        }

        let importedFileNames = await ConstructionMethodMediaImportSupport.importMediaItems(
            items,
            setProgressMessage: { message in
                tutorialMediaImportMessage = message
            },
            appendAttachment: { attachment in
                tutorialAttachments.append(attachment)
            },
            reportError: { message in
                showError(message)
            }
        )
        await MainActor.run {
            sessionAddedFileNames.formUnion(importedFileNames)
        }
    }

    func showError(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}
