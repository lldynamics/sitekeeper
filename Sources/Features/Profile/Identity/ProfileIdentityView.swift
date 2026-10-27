import SwiftUI
import PhotosUI

struct ProfileIdentityView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let displayUserName: String
    let appVersion: String
    let avatarImage: UIImage?
    let hasCustomAvatar: Bool
    let onChooseAvatar: () -> Void
    let onEditUserName: () -> Void
    let onResetAvatar: () -> Void

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.normal) {
                avatarPicker
                profileAccountDetails
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 14) {
                avatarPicker
                profileAccountDetails
            }
        }
    }

    private var profileAccountDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                onEditUserName()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(displayUserName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("编辑用户名"))
            .accessibilityIdentifier("profile-edit-username")
            Text("\(AppBrand.displayName) · v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var avatarPicker: some View {
        let image = avatarImage
        // The stable profile surface presents the picker while this card changes columns.
        return Button(action: onChooseAvatar) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .padding(2)
                            .foregroundStyle(Color.appPrimaryAction)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.appStrokeSecondary, lineWidth: 1)
                )

                Image(systemName: "camera.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Color.appPrimaryAction, in: Circle())
                    .offset(x: 1, y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.string("修改头像"))
        .accessibilityIdentifier("profile-avatar-picker")
        .contextMenu {
            if hasCustomAvatar {
                Button(role: .destructive) {
                    onResetAvatar()
                } label: {
                    Label(AppLocalization.string("恢复默认头像"), systemImage: "arrow.counterclockwise")
                }
            }
        }
    }
}
