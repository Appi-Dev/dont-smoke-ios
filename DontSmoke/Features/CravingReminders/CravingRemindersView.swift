import SwiftUI
import SwiftData

struct CravingRemindersView: View {
    @Bindable var profile: QuitProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @AppStorage("cravingRemindersEnabled") private var remindersEnabled = true
    @State private var permission: CravingNotificationPermission = .notDetermined

    var body: some View {
        List {
            permissionSection
            Section("Usual craving times") {
                if profile.triggers.isEmpty {
                    Text("No craving moments added yet.").foregroundStyle(.secondary)
                }
                ForEach(profile.triggers.sorted { $0.rawValue < $1.rawValue }) { trigger in
                    reminderRow(trigger)
                }
                Menu("Add craving moment", systemImage: "plus") {
                    ForEach(CravingTrigger.allCases.filter { !profile.triggers.contains($0) }) { trigger in
                        Button(trigger.title) { add(trigger) }
                    }
                }
            }
            Section {
                Toggle("Enable all craving reminders", isOn: $remindersEnabled).tint(AppColor.sage)
            } footer: {
                Text("Reminders arrive 10 minutes before the craving time you choose.")
            }
        }
        .navigationTitle("Craving Reminders")
        .task { permission = await NotificationService.scheduler.permission() }
        .onChange(of: remindersEnabled) { _, enabled in Task { await setAll(enabled) } }
    }

    @ViewBuilder private var permissionSection: some View {
        if permission == .denied {
            Section {
                Text("Notifications are currently disabled.")
                Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            }
        } else if permission == .notDetermined {
            Section {
                Text("Enable notifications when you’re ready for calm reminders before usual craving times.")
                Button("Enable reminders") { Task {
                    permission = await NotificationService.scheduler.requestAuthorizationIfNeeded()
                    profile.notificationPreference = permissionAllowsScheduling ? .enabled : .declined
                    try? modelContext.save()
                    if permissionAllowsScheduling { await setAll(remindersEnabled) }
                } }
            }
        }
    }

    @ViewBuilder private func reminderRow(_ trigger: CravingTrigger) -> some View {
        let schedule = profile.cravingSchedules.first { $0.triggerRaw == trigger.rawValue }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(trigger.title).font(.headline)
                Spacer()
                Toggle("Reminder for \(trigger.title)", isOn: Binding(
                    get: { schedule?.reminderEnabled == true },
                    set: { setEnabled($0, trigger: trigger, schedule: schedule) }
                )).labelsHidden().tint(AppColor.sage).disabled(!remindersEnabled)
            }
            if let schedule {
                DatePicker("Craving time", selection: Binding(get: { schedule.preferredTime }, set: { updateTime(schedule, to: $0) }), displayedComponents: .hourAndMinute)
                Text("Reminder at \(reminderTime(for: schedule.preferredTime).formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No reminder time set").font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button("Remove", role: .destructive) { remove(trigger, schedule: schedule) }
        }
    }

    private func add(_ trigger: CravingTrigger) {
        guard !profile.triggerRaws.contains(trigger.rawValue) else { return }
        profile.triggerRaws.append(trigger.rawValue); try? modelContext.save()
    }
    private func setEnabled(_ enabled: Bool, trigger: CravingTrigger, schedule: CravingSchedule?) {
        let item: CravingSchedule
        if let schedule { item = schedule }
        else {
            item = CravingSchedule(trigger: trigger, preferredTime: defaultTime(for: trigger)); item.profile = profile; modelContext.insert(item)
        }
        item.reminderEnabled = enabled; try? modelContext.save()
        Task {
            if enabled && remindersEnabled && permissionAllowsScheduling { await scheduleReminder(item) }
            else { await NotificationService.scheduler.cancelReminder(id: item.id) }
        }
    }
    private func updateTime(_ schedule: CravingSchedule, to time: Date) {
        schedule.preferredTime = time; try? modelContext.save()
        Task {
            await NotificationService.scheduler.cancelReminder(id: schedule.id)
            if schedule.reminderEnabled && remindersEnabled && permissionAllowsScheduling { await self.scheduleReminder(schedule) }
        }
    }
    private func remove(_ trigger: CravingTrigger, schedule: CravingSchedule?) {
        profile.triggerRaws.removeAll { $0 == trigger.rawValue }
        if let schedule { modelContext.delete(schedule); Task { await NotificationService.scheduler.cancelReminder(id: schedule.id) } }
        try? modelContext.save()
    }
    private func setAll(_ enabled: Bool) async {
        if !enabled { await NotificationService.scheduler.cancelAllCravingReminders(); return }
        guard permissionAllowsScheduling else { return }
        for item in profile.cravingSchedules where item.reminderEnabled { await scheduleReminder(item) }
    }
    private func scheduleReminder(_ item: CravingSchedule) async {
        await NotificationService.scheduler.scheduleReminder(id: item.id, trigger: item.trigger, cravingTime: item.preferredTime)
    }
    private var permissionAllowsScheduling: Bool { permission == .authorized || permission == .provisional }
    private func reminderTime(for date: Date) -> Date { Calendar.autoupdatingCurrent.date(byAdding: .minute, value: -10, to: date) ?? date }
    private func defaultTime(for trigger: CravingTrigger) -> Date {
        let hour: Int = switch trigger { case .morningCoffee: 8; case .afterBreakfast: 9; case .afterLunch: 14; case .afterDinner: 21; case .lateNight: 22; default: 12 }
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
    }
}
