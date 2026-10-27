import SwiftUI

struct RepositorySummaryRow: View {
    let item: RepositoryListItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title.isEmpty ? AppLocalization.string("未命名记录") : item.title).lineLimit(3)
                .foregroundStyle(.primary)
            Text(item.sortKey).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct RepositoryOrderPicker: View {
    @Binding var order: RepositoryOrder
    var body: some View {
        Picker(AppLocalization.string("日期顺序"), selection: $order) {
            Text(AppLocalization.string("由新到旧")).tag(RepositoryOrder.newestFirst)
            Text(AppLocalization.string("由旧到新")).tag(RepositoryOrder.oldestFirst)
        }
    }
}

struct RepositoryPageControls: View {
    let page: RepositoryPageModel
    var body: some View {
        Section {
            if page.isLoading { ProgressView().accessibilityLabel(AppLocalization.string("正在读取")) }
            if let message = page.errorMessage {
                Text(message).foregroundStyle(.secondary)
                Button(AppLocalization.string("重试")) { Task { await page.retry() } }
                    .disabled(page.isLoading)
            } else if page.items.isEmpty, !page.isLoading {
                Text(AppLocalization.string("没有匹配记录"))
            }
        }
    }
}

struct RepositoryPageNavigation: View {
    let page: RepositoryPageModel
    var body: some View {
        HStack {
            Button { Task { await page.previous() } } label: {
                Text(AppLocalization.string("上一页")).frame(minWidth: 44, minHeight: 44)
            }
            .disabled(page.isLoading || page.pageNumber == 1)
            .accessibilityIdentifier("repository-page-previous")
            Spacer()
            Text(String(format: AppLocalization.string("第 %lld 页"), Int64(page.pageNumber)))
                .accessibilityIdentifier("repository-page-number")
            Spacer()
            Button { Task { await page.next() } } label: {
                Text(AppLocalization.string("下一页")).frame(minWidth: 44, minHeight: 44)
            }
            .disabled(page.isLoading || page.nextCursor == nil)
            .accessibilityIdentifier("repository-page-next")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal)
        .background(.bar)
    }
}
