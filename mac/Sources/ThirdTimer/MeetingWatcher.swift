import EventKit
import Foundation

/// Reads the Mac's calendars to tell whether a meeting is running right now.
/// It only ever asks "is there one now?"; nothing is stored or sent anywhere.
@MainActor
final class MeetingWatcher: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var access: Access = .unknown
    private let store = EKEventStore()

    /// Asks macOS for calendar access; the first time, macOS shows its prompt.
    func requestAccess() {
        let done: @Sendable (Bool, Error?) -> Void = { [weak self] granted, _ in
            Task { @MainActor in self?.access = granted ? .granted : .denied }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: done)
        } else {
            store.requestAccess(to: .event, completion: done)
        }
    }

    /// True while a calendar event that counts as a meeting covers this moment.
    func inMeeting(at date: Date) -> Bool {
        guard access == .granted else { return false }
        let predicate = store.predicateForEvents(
            withStart: date, end: date.addingTimeInterval(1), calendars: nil)
        return store.events(matching: predicate).contains { event in
            // All-day entries, time marked as free, and cancelled or declined
            // invitations are not meetings you are sitting in.
            guard !event.isAllDay, event.availability != .free, event.status != .canceled else {
                return false
            }
            let mine = event.attendees?.first(where: { $0.isCurrentUser })
            return mine?.participantStatus != .declined
        }
    }
}
