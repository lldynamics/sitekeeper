import SwiftUI

extension WatermarkCameraToolView {
    func presentInfo(_ message: String) {
        presentToast(message, style: .success)
    }

    func presentError(_ message: String) {
        presentToast(message, style: .error)
    }

    func presentBlockingError(_ message: String, settingsURL: URL? = nil) {
        alertTitle = AppLocalization.string("wm_camera_alert_cannot_continue_title")
        alertMessage = message
        alertSettingsURL = settingsURL
        showAlert = true
    }

    func presentToast(_ message: String, style: WatermarkToastStyle) {
        let toast = WatermarkToast(message: message, style: style)
        withAnimation {
            self.toast = toast
        }
        Task { @MainActor in
            guard await DebouncedTask.wait(for: .seconds(2)) else { return }
            guard self.toast?.id == toast.id else { return }
            withAnimation {
                self.toast = nil
            }
        }
    }
}
