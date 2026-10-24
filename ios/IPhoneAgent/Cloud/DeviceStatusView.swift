import SwiftUI

extension CheckLevel {
    var color: Color {
        switch self {
        case .ready: return .green
        case .pending: return .orange
        case .attention: return .red
        }
    }
    var symbol: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .pending: return "circle.dashed"
        case .attention: return "exclamationmark.circle.fill"
        }
    }
}

struct DeviceStatusView: View {
    let readiness: DeviceReadiness
    let open: (DeviceCheck) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 5)
                    Circle().trim(from: 0, to: Double(readiness.completedCount) / 5)
                        .stroke(readiness.firstMissing == nil ? Color.green : .accentColor,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(readiness.completedCount)/5").font(.subheadline.monospacedDigit().bold())
                }.frame(width: 52, height: 52).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(readiness.firstMissing == nil ? "已准备好操控手机" : "完成配置，开始体验")
                        .font(.headline)
                    Text(readiness.firstMissing == nil ? "5 项检查已完成" : "\(readiness.completedCount) 项就绪 · 点击卡片查看指引")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            connectionRow
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(readiness.checks.filter { $0.id != .connection }) { item in
                    Button { open(item.id) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: item.id.symbol).font(.title3).foregroundStyle(item.level.color)
                                Spacer(minLength: 4)
                                Label(item.badge, systemImage: item.level.symbol)
                                    .font(.caption2.weight(.medium)).foregroundStyle(item.level.color)
                            }
                            HStack(spacing: 4) {
                                Text(item.id.title).font(.subheadline.weight(.semibold))
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }.foregroundStyle(.primary)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(item.level.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.id.title)，\(item.badge)，\(item.detail)")
                    .accessibilityHint(item.id == .usb ? "打开辅助触控设置，返回后自动检测" : "打开对应配置指引")
                    .accessibilityIdentifier("device-check-\(item.id.rawValue)")
                }
            }
            if let next = readiness.firstMissing {
                Button { open(next) } label: {
                    HStack {
                        Text("继续配置：\(next.title)").font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }.padding(.vertical, 4)
                }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }
        }.padding(.vertical, 6)
    }

    private var connectionRow: some View {
        let item = readiness.check(.connection)
        return Button { open(.connection) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.id.symbol).foregroundStyle(item.level.color)
                Text(item.id.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Spacer(minLength: 4)
                Label(item.badge, systemImage: item.level.symbol).font(.caption).foregroundStyle(item.level.color)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }.padding(12).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("设备连接，\(item.badge)，\(item.detail)")
        .accessibilityHint("打开连接设置")
        .accessibilityIdentifier("device-check-connection")
    }
}

