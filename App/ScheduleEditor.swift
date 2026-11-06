import CopyFXCore
import SwiftUI

struct ScheduleEditor: View {
    private enum Frequency: String, CaseIterable {
        case manual = "Manually"
        case interval = "Every few minutes or hours"
        case hourly = "Every hour"
        case weekdays = "On days of the week"
        case monthDays = "On days of the month"
    }

    private enum IntervalUnit: String, CaseIterable {
        case minutes = "Minutes"
        case hours = "Hours"
    }

    private static let defaultTimes = [ScheduleTime(hour: 2, minute: 0)]

    @Binding var schedule: Schedule
    @State private var unit = IntervalUnit.hours

    private var current: Schedule { schedule.normalized }

    private var frequency: Frequency {
        switch current {
        case .interval: .interval
        case .hourly: .hourly
        case .weekdays: .weekdays
        case .monthDays: .monthDays
        default: .manual
        }
    }

    private var times: [ScheduleTime] {
        switch current {
        case .weekdays(_, let times), .monthDays(_, let times): times
        default: Self.defaultTimes
        }
    }

    var body: some View {
        Picker("Run", selection: frequencyBinding) {
            ForEach(Frequency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }

        switch current {
        case .interval(let minutes):
            intervalRows(minutes: minutes)
        case .hourly(let minute):
            Stepper(value: Binding(get: { minute }, set: { schedule = .hourly(minute: $0) }), in: 0...59) {
                Text("At \(minute) minutes past the hour")
            }
        case .weekdays(let days, let times):
            WeekdayPicker(days: Binding(get: { days }, set: { schedule = .weekdays(days: $0, times: times) }))
            TimeList(times: Binding(get: { times }, set: { schedule = .weekdays(days: days, times: $0) }))
        case .monthDays(let days, let times):
            MonthDayPicker(days: Binding(get: { days }, set: { schedule = .monthDays(days: $0, times: times) }))
            TimeList(times: Binding(get: { times }, set: { schedule = .monthDays(days: days, times: $0) }))
            if days.contains(where: { $0 > 28 }) {
                Text("Months without a chosen day skip it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }

        if frequency != .manual {
            VStack(alignment: .leading, spacing: 2) {
                if let next = schedule.nextRun() {
                    Text("Next run: \(next.formatted(date: .complete, time: .shortened))")
                        .fontWeight(.medium)
                }
                Text("Runs even when CopyFX is closed. If your Mac is asleep, the backup runs when it wakes.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func intervalRows(minutes: Int) -> some View {
        Picker("Unit", selection: unitBinding(minutes: minutes)) {
            ForEach(IntervalUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .onAppear {
            if minutes % 60 != 0 { unit = .minutes }
        }

        if unit == .hours {
            let hours = max(1, minutes / 60)
            Stepper(value: Binding(get: { hours }, set: { schedule = .interval(minutes: $0 * 60) }), in: 1...24) {
                Text("Every \(hours) \(hours == 1 ? "hour" : "hours")")
            }
        } else {
            Stepper(value: Binding(get: { minutes }, set: { schedule = .interval(minutes: $0) }), in: 5...720, step: 5) {
                Text("Every \(minutes) minutes")
            }
        }
    }

    private func unitBinding(minutes: Int) -> Binding<IntervalUnit> {
        Binding(
            get: { unit },
            set: { newUnit in
                unit = newUnit
                if newUnit == .hours {
                    schedule = .interval(minutes: max(1, (minutes + 30) / 60) * 60)
                }
            }
        )
    }

    private var frequencyBinding: Binding<Frequency> {
        Binding(
            get: { frequency },
            set: { newValue in
                switch newValue {
                case .manual:
                    schedule = .manual
                case .interval:
                    unit = .hours
                    schedule = .interval(minutes: 240)
                case .hourly:
                    schedule = .hourly(minute: 0)
                case .weekdays:
                    schedule = .weekdays(days: Schedule.allWeekdays, times: times)
                case .monthDays:
                    schedule = .monthDays(days: [1], times: times)
                }
            }
        )
    }
}

private struct WeekdayPicker: View {
    @Binding var days: [Int]

    /// Indexes into the calendar's Sunday-first list, starting on the user's first weekday.
    private var ordered: [Int] {
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { ($0 + first) % 7 }
    }

    var body: some View {
        LabeledContent("Days") {
            HStack(spacing: 4) {
                ForEach(ordered, id: \.self) { day in
                    Toggle(isOn: selected(day)) {
                        Text(Calendar.current.shortWeekdaySymbols[day])
                            .frame(minWidth: 30)
                    }
                    .toggleStyle(.button)
                }
            }
        }
        LabeledContent("Quick choice") {
            HStack {
                Button("Every Day") { days = Schedule.allWeekdays }
                Button("Weekdays") { days = [1, 2, 3, 4, 5] }
                Button("Weekends") { days = [0, 6] }
            }
        }
    }

    private func selected(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { days.contains(day) },
            set: { isOn in
                if isOn {
                    days.append(day)
                } else if days.count > 1 {
                    days.removeAll { $0 == day }
                }
            }
        )
    }
}

private struct MonthDayPicker: View {
    @Binding var days: [Int]

    private let columns = Array(repeating: GridItem(.fixed(38), spacing: 4), count: 7)

    var body: some View {
        LabeledContent("Days") {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(1...31, id: \.self) { day in
                    Toggle(isOn: selected(day)) {
                        Text(day, format: .number)
                            .monospacedDigit()
                            .frame(minWidth: 22)
                    }
                    .toggleStyle(.button)
                }
            }
            .fixedSize()
        }
    }

    private func selected(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { days.contains(day) },
            set: { isOn in
                if isOn {
                    days.append(day)
                } else if days.count > 1 {
                    days.removeAll { $0 == day }
                }
            }
        )
    }
}

private struct TimeList: View {
    @Binding var times: [ScheduleTime]

    var body: some View {
        ForEach(times.indices, id: \.self) { index in
            HStack {
                DatePicker(times.count == 1 ? "Time" : "Time \(index + 1)", selection: time(at: index), displayedComponents: .hourAndMinute)
                if times.count > 1 {
                    Button {
                        times.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this time")
                }
            }
        }
        HStack {
            Spacer()
            Button("Add Time") {
                let last = times.last ?? ScheduleTime(hour: 2, minute: 0)
                times.append(ScheduleTime(hour: (last.hour + 1) % 24, minute: last.minute))
            }
        }
    }

    private func time(at index: Int) -> Binding<Date> {
        Binding(
            get: {
                guard times.indices.contains(index) else { return Date() }
                let time = times[index]
                return Calendar.current.date(from: DateComponents(hour: time.hour, minute: time.minute)) ?? Date()
            },
            set: { date in
                guard times.indices.contains(index) else { return }
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                times[index] = ScheduleTime(hour: components.hour ?? 0, minute: components.minute ?? 0)
            }
        )
    }
}
