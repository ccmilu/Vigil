import SwiftUI
import SwiftData

struct StreakCard: View {
    @Query private var streaks: [StreakInfo]

    private var info: StreakInfo? { streaks.first }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(streakColor)
                Text("\(info?.currentStreak ?? 0)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("连续打卡天数")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("最长 \(info?.longestStreak ?? 0) 天")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let last = info?.lastActiveDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("上次打卡")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(last.formatted(.dateTime.month().day()))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.08), Color.red.opacity(0.04)],
                startPoint: .leading, endPoint: .trailing
            ),
            in: .rect(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.15), lineWidth: 1)
        )
    }

    private var streakColor: Color {
        switch info?.currentStreak ?? 0 {
        case 0:    return .secondary
        case 1...2: return .orange
        case 3...6: return .red
        default:   return .pink
        }
    }
}
