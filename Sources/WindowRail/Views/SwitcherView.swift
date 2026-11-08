import AppKit
import SwiftUI
import Combine
import ApplicationServices

struct WindowRow: View {
    let entry: WindowEntry
    var selected = false
    var current = false
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 5) {
            if let icon = entry.app.icon {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 20, height: 20)
            }
            Text(entry.title)
                .font(.system(size: 14)).foregroundStyle(selected ? Color.white : Color.primary)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if current {
                Text(L10n.text(.windowCurrent))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((selected ? Color.white : Color.primary).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .fixedSize()
                    .accessibilityLabel(L10n.text(.windowCurrentAccessibility))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 26).padding(.horizontal, 7)
        .background(selected ? Color(nsColor: .selectedContentBackgroundColor) : (hovering ? Color.primary.opacity(0.07) : Color.clear))
        .clipped().contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(entry.title)
    }
}
struct SwitcherView: View {
    @ObservedObject var model: WindowModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text(.switcherTitle)).font(.headline)
                Spacer()
                Text(L10n.text(.switcherHelp)).font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 10).padding(.top, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(model.choices.enumerated()), id: \.element.id) { index, entry in
                            WindowRow(entry: entry, selected: index == model.selection, current: entry.id == model.originWindowID).id(index)
                        }
                    }
                }.onReceive(model.$selection.removeDuplicates()) { index in proxy.scrollTo(index, anchor: .center) }
                .onAppear { proxy.scrollTo(model.selection, anchor: .center) }
            }
        }.padding(10).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
