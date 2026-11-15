import GesherPlatform
import Foundation

/// Calendar and event writes through CalendarDaemon transactions. Every write is read back
/// through a fresh native read; deletes check native absence.
public final class CalendarWriteRepository: @unchecked Sendable {
    private let runtime: CalendarRuntime
    private let read: CalendarReadRepository

    public init(runtime: CalendarRuntime, readRepository: CalendarReadRepository) {
        self.runtime = runtime
        self.read = readRepository
    }

    // MARK: Calendars

    public func createCalendar(title: String, colorHex: String?, sourceID: String) throws -> CalendarSnapshot {
        let trimmed = try Self.title(title, type: "Calendar")
        let id = try runtime.session { session -> String in
            let source = try CalendarSession.objectID(sourceID, entity: "Source", type: CalendarEntityType.source)
            let changes = CalendarChangeSet(database: CalendarSession.database(of: source))
            var values: [String: Any] = [
                "UUID": UUID().uuidString, "unlocalizedTitle": trimmed, "source": source, "allowedEntities": 4,
            ]
            if let colorHex { values["colorStringRaw"] = colorHex.uppercased() }
            let temporary = try changes.insert(CalendarEntityType.calendar, values)
            return try Self.permanentID(try session.commit(changes), temporary, type: "calendar")
        }
        let saved = try MutationVerification.readback(type: "calendar", id: id) { try read.fetchCalendar(id: id) }
        guard saved.title == trimmed, colorHex == nil || saved.colorHex?.uppercased() == colorHex?.uppercased() else {
            throw PlatformError.saveFailed(
                "Calendar \(id) did not read back as written; inspect it before retrying.")
        }
        return saved
    }

    public func updateCalendar(id: String, title: String?, colorHex: String?) throws -> CalendarSnapshot {
        var values: [String: Any] = [:]
        if let title { values["unlocalizedTitle"] = try Self.title(title, type: "Calendar") }
        if let colorHex { values["colorStringRaw"] = colorHex.uppercased() }
        guard !values.isEmpty else {
            throw AgentError.invalid("Nothing to change.", hint: "Pass a new title and/or color.")
        }
        try runtime.session { session in
            let object = try CalendarSession.objectID(id, entity: "Calendar", type: CalendarEntityType.calendar)
            let changes = CalendarChangeSet(database: CalendarSession.database(of: object))
            try changes.set(object, values)
            try session.commit(changes)
        }
        let saved = try MutationVerification.readback(type: "calendar", id: id) { try read.fetchCalendar(id: id) }
        guard values["unlocalizedTitle"].map({ saved.title == $0 as? String }) ?? true,
            colorHex.map({ saved.colorHex?.uppercased() == $0.uppercased() }) ?? true
        else {
            throw PlatformError.saveFailed(
                "Calendar \(id) did not read back as written; inspect it before retrying.")
        }
        return saved
    }

    public func deleteCalendar(id: String) throws {
        try runtime.session { session in
            let object = try CalendarSession.objectID(id, entity: "Calendar", type: CalendarEntityType.calendar)
            let changes = CalendarChangeSet(database: CalendarSession.database(of: object))
            changes.delete([object])
            try session.commit(changes)
            guard try !session.exists(object) else {
                throw PlatformError.saveFailed(
                    "Calendar \(id) still exists after delete; inspect before retrying.")
            }
        }
    }

    // MARK: Events

    public func createEvent(_ draft: EventDraft) throws -> CalendarEventSnapshot {
        let id = try runtime.session { session -> String in
            let calendar = try CalendarSession.objectID(
                draft.calendarID, entity: "Calendar", type: CalendarEntityType.calendar)
            let changes = CalendarChangeSet(database: CalendarSession.database(of: calendar))
            let event = try insertEvent(draft, calendar: calendar, extra: [:], into: changes)
            return try Self.permanentID(try session.commit(changes), event, type: "event")
        }
        let saved = try MutationVerification.readback(type: "event", id: id) { try read.fetchEvent(id: id) }
        try Self.verify(saved, matches: draft)
        return saved
    }

    /// Applies `changes` to an event. For a recurring event `scope` picks the occurrences:
    /// `this` detaches one occurrence, `future` splits the series at it, `all` edits the series.
    public func updateEvent(id: String, changes: EventChanges, scope: RecurrenceScope?) throws -> CalendarEventSnapshot
    {
        guard !changes.isEmpty else {
            throw AgentError.invalid("Nothing to change.", hint: "Pass at least one field to update.")
        }
        let current = try read.fetchEvent(id: id)
        let scope = try Self.scope(scope, for: current)
        if current.isRecurring && scope != .all && changes.calendarID != nil && changes.calendarID != current.calendarID
        {
            throw AgentError.invalid(
                "Only a whole series can move to another calendar.", hint: "Retry with scope all.")
        }
        switch (current.isRecurring, scope) {
        case (false, _), (true, .all):
            return try updateWhole(current, changes)
        case (true, .this):
            if current.seriesID != current.nativeID {
                return try updateWhole(current, changes, keepRecurrence: true)  // already a detached occurrence
            }
            return try detach(current, changes)
        case (true, .future):
            return try split(current, changes)
        }
    }

    /// Deletes an event, or for a recurring event the occurrences selected by `scope`.
    public func deleteEvent(id: String, scope: RecurrenceScope?) throws {
        let current = try read.fetchEvent(id: id)
        let scope = try Self.scope(scope, for: current)
        try runtime.session { session in
            let event = try CalendarSession.objectID(current.nativeID, entity: "Event", type: CalendarEntityType.event)
            let changes = CalendarChangeSet(database: CalendarSession.database(of: event))
            let masterID = current.seriesID ?? current.nativeID
            let master = try read.nativeEvent(masterID, session: session)
            let masterStart = master.date("startDateRaw") ?? current.start
            let occurrence = current.occurrenceDate ?? current.start
            switch (current.isRecurring, scope) {
            case (false, _), (true, .all):
                changes.delete([master.id] + master.related("detachedItems"))
            case (true, .future) where occurrence <= masterStart:
                changes.delete([master.id] + master.related("detachedItems"))
            case (true, .this):
                if masterID != current.nativeID { changes.delete([event]) }
                try addException(occurrence, to: master, into: changes)
            case (true, .future):
                try endSeries(master, before: occurrence, into: changes, session: session)
            }
            try session.commit(changes)
            if !current.isRecurring || scope == .all || (scope == .future && occurrence <= masterStart) {
                guard try !session.exists(master.id) else {
                    throw PlatformError.saveFailed(
                        "Event \(id) still exists after delete; inspect before retrying.")
                }
            }
        }
        if current.isRecurring && scope != .all {
            let remaining = try read.fetchEvents(
                start: current.start,
                end: current.start.addingTimeInterval(max(60, current.end.timeIntervalSince(current.start))),
                calendarIDs: [current.calendarID])
            guard !remaining.contains(where: { $0.id == current.id }) else {
                throw PlatformError.saveFailed(
                    "Occurrence \(id) is still listed after delete; inspect the series before retrying.")
            }
        }
    }

    /// Sets the user's participation status on an invitation (accept / decline / tentative).
    public func respond(id: String, status: ParticipantStatus) throws -> CalendarEventSnapshot {
        let current = try read.fetchEvent(id: id)
        guard current.selfStatus != nil else {
            throw AgentError(
                code: "not_an_invitation", message: "'\(current.title)' has no invitation for you to answer.",
                hint: "List pending invitations with invitation list.")
        }
        try runtime.session { session in
            let event = try read.nativeEvent(current.nativeID, session: session)
            let changes = CalendarChangeSet(database: CalendarSession.database(of: event.id))
            guard let attendee = event.related("selfAttendee").first else {
                throw AgentError(
                    code: "not_an_invitation", message: "'\(current.title)' has no attendee entry for you.",
                    hint: "Only invitations received through a calendar account can be answered.")
            }
            try changes.set(attendee, ["statusRaw": status.rawValue])
            try changes.set(event.id, ["selfParticipantStatusRaw": status.rawValue, "invitationStatus": 0])
            try session.commit(changes)
        }
        let saved = try MutationVerification.readback(type: "event", id: id) { try read.fetchEvent(id: id) }
        guard saved.selfStatus == status else {
            throw PlatformError.saveFailed(
                "The response did not read back; inspect the invitation before retrying.")
        }
        return saved
    }

    // MARK: Scoped edits

    private func updateWhole(_ current: CalendarEventSnapshot, _ changes: EventChanges, keepRecurrence: Bool = false)
        throws -> CalendarEventSnapshot
    {
        let targetID =
            current.isRecurring && !keepRecurrence ? (current.seriesID ?? current.nativeID) : current.nativeID
        var shifted = changes
        try runtime.session { session in
            let entity = try read.nativeEvent(targetID, session: session)
            // When an occurrence of a series was selected, move the master by the same amount.
            let offset = (entity.date("startDateRaw") ?? current.start).timeIntervalSince(current.start)
            let duration = current.end.timeIntervalSince(current.start)
            shifted.start = changes.start.map { $0.addingTimeInterval(offset) }
            shifted.end =
                changes.end.map { $0.addingTimeInterval(offset) }
                ?? shifted.start.map { $0.addingTimeInterval(duration) }
            let set = CalendarChangeSet(database: CalendarSession.database(of: entity.id))
            try apply(shifted, to: entity, into: set, session: session)
            // As Calendar does for "all events": occurrences edited on their own (detached) get the
            // same field changes; their own times stay.
            if current.isRecurring && !keepRecurrence {
                var common = changes
                common.start = nil
                common.end = nil
                common.isAllDay = nil
                common.timeZone = nil
                common.recurrence = nil
                common.calendarID = nil
                if !common.isEmpty {
                    for detached in entity.related("detachedItems") {
                        guard let id = try? CalendarSession.string(detached),
                            let row = try? read.nativeEvent(id, session: session)
                        else { continue }
                        try apply(common, to: row, into: set, session: session)
                    }
                }
            }
            try session.commit(set)
        }
        let saved = try MutationVerification.readback(type: "event", id: targetID) { try read.fetchEvent(id: targetID) }
        try Self.verify(saved, applied: shifted)
        return saved
    }

    private func detach(_ current: CalendarEventSnapshot, _ changes: EventChanges) throws -> CalendarEventSnapshot {
        guard changes.recurrence == nil else {
            throw AgentError.invalid(
                "A single occurrence cannot have its own repeat rule.", hint: "Use scope all or future.")
        }
        var draft = Self.draft(from: current, changes)
        draft.recurrence = nil
        let occurrence = current.occurrenceDate ?? current.start
        let id = try runtime.session { session -> String in
            let master = try read.nativeEvent(current.nativeID, session: session)
            let calendar = try CalendarSession.objectID(
                current.calendarID, entity: "Calendar", type: CalendarEntityType.calendar)
            let set = CalendarChangeSet(database: CalendarSession.database(of: master.id))
            var extra: [String: Any] = ["originalItem": master.id, "originalStartDate": occurrence]
            if let uniqueID = master.string("uniqueID") { extra["uniqueID"] = uniqueID }
            let detached = try insertEvent(draft, calendar: calendar, extra: extra, into: set)
            try set.set(master.id, ["detachedItems": NSSet(array: master.related("detachedItems") + [detached])])
            return try Self.permanentID(try session.commit(set), detached, type: "event")
        }
        let saved = try MutationVerification.readback(type: "event", id: id) { try read.fetchEvent(id: id) }
        try Self.verify(saved, matches: draft)
        return saved
    }

    private func split(_ current: CalendarEventSnapshot, _ changes: EventChanges) throws -> CalendarEventSnapshot {
        let occurrence = current.occurrenceDate ?? current.start
        let masterID = current.seriesID ?? current.nativeID
        let master = try read.fetchEvent(id: masterID)
        if occurrence <= master.start { return try updateWhole(current, changes) }
        var draft = Self.draft(from: current, changes)
        if changes.recurrence == nil, var rule = master.recurrence {
            if let count = rule.count {
                let before = try read.fetchEvents(
                    start: master.start, end: occurrence, calendarIDs: [master.calendarID]
                )
                .filter { $0.seriesID == masterID }.count
                rule.count = max(1, count - before)
            }
            draft.recurrence = rule
        }
        let id = try runtime.session { session -> String in
            let native = try read.nativeEvent(masterID, session: session)
            let calendar = try CalendarSession.objectID(
                draft.calendarID, entity: "Calendar", type: CalendarEntityType.calendar)
            let set = CalendarChangeSet(database: CalendarSession.database(of: native.id))
            try endSeries(native, before: occurrence, into: set, session: session)
            let created = try insertEvent(draft, calendar: calendar, extra: [:], into: set)
            return try Self.permanentID(try session.commit(set), created, type: "event")
        }
        let saved = try MutationVerification.readback(type: "event", id: id) { try read.fetchEvent(id: id) }
        try Self.verify(saved, matches: draft)
        let truncated = try read.fetchEvent(id: masterID)
        guard let until = truncated.recurrence?.until, until < occurrence else {
            throw PlatformError.saveFailed(
                "The original series was not ended before the split; inspect \(masterID) before retrying.")
        }
        return saved
    }

    // MARK: Native field writes

    private func insertEvent(
        _ draft: EventDraft, calendar: AnyObject, extra: [String: Any], into set: CalendarChangeSet
    ) throws -> AnyObject {
        let title = try Self.title(draft.title, type: "Event")
        guard draft.end > draft.start else { throw AgentError.invalid("The event must end after it starts.") }
        let zone = draft.isAllDay ? EventDates.floating : draft.timeZone.identifier
        var values: [String: Any] = [
            "UUID": UUID().uuidString, "unlocalizedTitle": title, "calendar": calendar, "startDateRaw": draft.start,
            "endDateRaw": draft.end, "isAllDay": draft.isAllDay, "startTimeZoneName": zone, "endTimeZoneName": zone,
        ]
        if let notes = draft.notes, !notes.isEmpty { values["notes"] = notes }
        if let url = draft.url, !url.isEmpty { values["URLString"] = url }
        if let availability = draft.availability { values["availability"] = availability.rawValue }
        if let travel = draft.travelTimeSeconds { values["travelTime"] = travel }
        for (key, value) in extra { values[key] = value }
        let event = try set.insert(CalendarEntityType.event, values)
        if let location = draft.location {
            try set.set(event, ["structuredLocationWithoutPrediction": try insertLocation(location, owner: event, set)])
        }
        if let alerts = draft.alerts { try writeAlerts(alerts, owner: event, existing: [], set) }
        if let rule = draft.recurrence { try writeRecurrence(rule, owner: event, existing: [], set) }
        if !draft.attendees.isEmpty {
            try writeAttendees(add: draft.attendees, remove: [], owner: event, existing: [], set)
        }
        return event
    }

    private func apply(
        _ changes: EventChanges, to entity: NativeCalendarEntity, into set: CalendarChangeSet, session: CalendarSession
    ) throws {
        var values: [String: Any] = [:]
        if let title = changes.title { values["unlocalizedTitle"] = try Self.title(title, type: "Event") }
        if let notes = changes.notes { values["notes"] = notes.isEmpty ? NSNull() : notes }
        if let url = changes.url { values["URLString"] = url.isEmpty ? NSNull() : url }
        if let start = changes.start { values["startDateRaw"] = start }
        if let end = changes.end { values["endDateRaw"] = end }
        let allDay = changes.isAllDay ?? (entity.number("isAllDay")?.boolValue ?? false)
        if let flag = changes.isAllDay { values["isAllDay"] = flag }
        if changes.isAllDay != nil || changes.timeZone != nil {
            let zone = allDay ? EventDates.floating : (changes.timeZone ?? .current).identifier
            values["startTimeZoneName"] = zone
            values["endTimeZoneName"] = zone
        }
        if let start = (changes.start ?? entity.date("startDateRaw")),
            let end = (changes.end ?? entity.date("endDateRaw")),
            end <= start
        {
            throw AgentError.invalid("The event must end after it starts.")
        }
        if let availability = changes.availability { values["availability"] = availability.rawValue }
        if let travel = changes.travelTimeSeconds { values["travelTime"] = travel }
        if let calendarID = changes.calendarID {
            values["calendar"] = try CalendarSession.objectID(
                calendarID, entity: "Calendar", type: CalendarEntityType.calendar)
        }
        if changes.clearLocation {
            values["structuredLocationWithoutPrediction"] = NSNull()
            set.delete(entity.related("structuredLocationWithoutPrediction"))
        } else if let location = changes.location {
            set.delete(entity.related("structuredLocationWithoutPrediction"))
            values["structuredLocationWithoutPrediction"] = try insertLocation(location, owner: entity.id, set)
        }
        try set.set(entity.id, values)
        if let alerts = changes.alerts {
            try writeAlerts(alerts, owner: entity.id, existing: entity.related("allAlarmsSet"), set)
        }
        if let recurrence = changes.recurrence {
            if let rule = recurrence {
                try writeRecurrence(rule, owner: entity.id, existing: entity.related("recurrenceRulesSet"), set)
            } else {
                set.delete(entity.related("recurrenceRulesSet") + entity.related("detachedItems"))
                try set.set(
                    entity.id,
                    ["recurrenceRulesSet": NSSet(), "hasRecurrenceRules": false, "ekExceptionDates": NSSet()])
                set.delete(entity.related("ekExceptionDates"))
            }
        }
        if !changes.invite.isEmpty || !changes.uninvite.isEmpty {
            let attendees = try session.properties(
                entity.related("attendeesRaw"), keys: ["emailAddress", "URLString"])
            let removing = attendees.filter { row in
                let email =
                    (row.string("emailAddress")
                    ?? row.string("URLString")?.replacingOccurrences(of: "mailto:", with: ""))?
                    .lowercased()
                return email.map { changes.uninvite.map { $0.lowercased() }.contains($0) } ?? false
            }
            let known = Set(attendees.compactMap { $0.string("emailAddress")?.lowercased() })
            try writeAttendees(
                add: changes.invite.filter { !known.contains($0.email.lowercased()) }, remove: removing.map(\.id),
                owner: entity.id, existing: entity.related("attendeesRaw"), set)
        }
    }

    private func insertLocation(_ location: LocationInput, owner: AnyObject, _ set: CalendarChangeSet) throws
        -> AnyObject
    {
        var values: [String: Any] = ["title": location.title, "calendarItemOwner": owner]
        if let address = location.address { values["address"] = address }
        if let latitude = location.latitude, let longitude = location.longitude {
            values["latitude"] = latitude
            values["longitude"] = longitude
        }
        return try set.insert(CalendarEntityType.location, values)
    }

    private func writeAlerts(_ alerts: [AlertSpec], owner: AnyObject, existing: [AnyObject], _ set: CalendarChangeSet)
        throws
    {
        set.delete(existing)
        let ids = try alerts.map { alert -> AnyObject in
            var values: [String: Any] = [
                "UUID": UUID().uuidString, "calendarItemOwner": owner, "type": 0, "isDefaultAlarm": false,
            ]
            switch alert {
            case .before(let minutes): values["relativeOffset"] = -Double(minutes) * 60
            case .at(let date): values["absoluteDate"] = date
            }
            return try set.insert(CalendarEntityType.alarm, values)
        }
        try set.set(owner, ["allAlarmsSet": NSSet(array: ids), "defaultAlarmWasDeleted": true])
    }

    private func writeRecurrence(
        _ rule: RecurrenceRule, owner: AnyObject, existing: [AnyObject], _ set: CalendarChangeSet
    )
        throws
    {
        try rule.validate()
        set.delete(existing)
        var values: [String: Any] = [
            "UUID": UUID().uuidString, "owner": owner, "frequencyRaw": rule.frequency.nativeRaw,
            "interval": rule.interval, "count": rule.count ?? 0,
        ]
        values["specifier"] = rule.specifier ?? NSNull()
        values["endDate"] = rule.until ?? NSNull()
        let id = try set.insert(CalendarEntityType.recurrenceRule, values)
        try set.set(owner, ["recurrenceRulesSet": NSSet(array: [id]), "hasRecurrenceRules": true])
    }

    private func writeAttendees(
        add: [AttendeeInput], remove: [AnyObject], owner: AnyObject, existing: [AnyObject], _ set: CalendarChangeSet
    ) throws {
        set.delete(remove)
        let removed = Set(remove.compactMap { try? CalendarSession.string($0) })
        let kept = existing.filter { !removed.contains((try? CalendarSession.string($0)) ?? "") }
        let added = try add.map { attendee -> AnyObject in
            var values: [String: Any] = [
                "UUID": UUID().uuidString, "owner": owner, "emailAddress": attendee.email,
                "URLString": "mailto:" + attendee.email, "statusRaw": ParticipantStatus.pending.rawValue,
                "participantRole": 1, "participantType": 1,
            ]
            if let name = attendee.name { values["displayNameRaw"] = name }
            return try set.insert(CalendarEntityType.attendee, values)
        }
        try set.set(owner, ["attendeesRaw": NSSet(array: kept + added), "hasAttendees": !(kept + added).isEmpty])
    }

    private func addException(_ date: Date, to master: NativeCalendarEntity, into set: CalendarChangeSet) throws {
        let exception = try set.insert(CalendarEntityType.exceptionDate, ["owner": master.id, "date": date])
        try set.set(master.id, ["ekExceptionDates": NSSet(array: master.related("ekExceptionDates") + [exception])])
    }

    /// Ends a series just before `occurrence` and removes detached occurrences from then on.
    private func endSeries(
        _ master: NativeCalendarEntity, before occurrence: Date, into set: CalendarChangeSet, session: CalendarSession
    ) throws {
        guard let rule = master.related("recurrenceRulesSet").first else {
            throw PlatformError.fetchFailed("The series has no readable repeat rule.")
        }
        try set.set(rule, ["endDate": occurrence.addingTimeInterval(-1), "count": 0])
        let detached = try session.properties(master.related("detachedItems"), keys: ["originalStartDate"])
        set.delete(detached.filter { ($0.date("originalStartDate") ?? .distantPast) >= occurrence }.map(\.id))
    }

    // MARK: Helpers

    static func scope(_ scope: RecurrenceScope?, for event: CalendarEventSnapshot) throws -> RecurrenceScope {
        guard event.isRecurring else { return .all }
        guard let scope else {
            throw AgentError(
                code: "scope_required",
                message: "'\(event.title)' repeats; say which occurrences to change.",
                hint: "Retry with scope this (only this occurrence), future (this and following) or all (whole series)."
            )
        }
        return scope
    }

    static func title(_ value: String, type: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AgentError.invalid("\(type) title cannot be empty.") }
        return trimmed
    }

    static func permanentID(_ map: NSDictionary, _ temporary: AnyObject, type: String) throws -> String {
        guard let created = map.object(forKey: temporary), let id = NativeCalendarEntity.identifier(of: created) else {
            throw PlatformError.saveFailed(
                "CalendarDaemon committed but did not return the new \(type) id. List \(type)s before retrying.")
        }
        return id
    }

    /// The full state of `event` with `changes` applied, as a draft for a new entity.
    static func draft(from event: CalendarEventSnapshot, _ changes: EventChanges) -> EventDraft {
        let start = changes.start ?? event.start
        let end = changes.end ?? start.addingTimeInterval(event.end.timeIntervalSince(event.start))
        let removed = Set(changes.uninvite.map { $0.lowercased() })
        let attendees =
            event.attendees.filter { !$0.isCurrentUser }.compactMap { attendee in
                attendee.email.map { AttendeeInput(email: $0, name: attendee.name) }
            }.filter { !removed.contains($0.email.lowercased()) } + changes.invite
        return EventDraft(
            calendarID: changes.calendarID ?? event.calendarID, title: changes.title ?? event.title, start: start,
            end: end, isAllDay: changes.isAllDay ?? event.isAllDay,
            timeZone: changes.timeZone ?? event.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current,
            location: changes.clearLocation
                ? nil
                : changes.location
                    ?? event.location.map {
                        LocationInput(
                            title: $0.title, address: $0.address, latitude: $0.latitude, longitude: $0.longitude)
                    },
            notes: changes.notes ?? event.notes, url: changes.url ?? event.url,
            availability: changes.availability ?? event.availability,
            travelTimeSeconds: changes.travelTimeSeconds ?? event.travelTimeSeconds,
            alerts: changes.alerts ?? event.alerts.map(\.spec),
            recurrence: changes.recurrence ?? event.recurrence, attendees: attendees)
    }

    static func verify(_ saved: CalendarEventSnapshot, matches draft: EventDraft) throws {
        var mismatches: [String] = []
        if saved.title != draft.title.trimmingCharacters(in: .whitespacesAndNewlines) { mismatches.append("title") }
        if saved.calendarID != draft.calendarID { mismatches.append("calendar") }
        if abs(saved.start.timeIntervalSince(draft.start)) > 1 || abs(saved.end.timeIntervalSince(draft.end)) > 1 {
            mismatches.append("time")
        }
        if saved.isAllDay != draft.isAllDay { mismatches.append("allDay") }
        if saved.location?.title != draft.location?.title { mismatches.append("location") }
        if (saved.notes ?? "") != (draft.notes ?? "") { mismatches.append("notes") }
        if (saved.url ?? "") != (draft.url ?? "") { mismatches.append("url") }
        if let availability = draft.availability, saved.availability != availability {
            mismatches.append("availability")
        }
        if (saved.travelTimeSeconds ?? 0) != (draft.travelTimeSeconds ?? 0) { mismatches.append("travelTime") }
        if let alerts = draft.alerts, !AlertSpec.same(saved.alerts.map(\.spec), alerts) { mismatches.append("alerts") }
        if saved.recurrence?.rrule != draft.recurrence?.rrule { mismatches.append("repeat") }
        let emails = Set(saved.attendees.compactMap { $0.email?.lowercased() })
        if !draft.attendees.allSatisfy({ emails.contains($0.email.lowercased()) }) { mismatches.append("attendees") }
        guard mismatches.isEmpty else {
            throw PlatformError.saveFailed(
                "Event \(saved.id) did not read back as written (\(mismatches.joined(separator: ", "))); inspect it before retrying."
            )
        }
    }

    static func verify(_ saved: CalendarEventSnapshot, applied changes: EventChanges) throws {
        var mismatches: [String] = []
        if let title = changes.title, saved.title != title.trimmingCharacters(in: .whitespacesAndNewlines) {
            mismatches.append("title")
        }
        if let calendarID = changes.calendarID, saved.calendarID != calendarID { mismatches.append("calendar") }
        if let start = changes.start, abs(saved.start.timeIntervalSince(start)) > 1 {
            mismatches.append("start")
        }
        if let end = changes.end, abs(saved.end.timeIntervalSince(end)) > 1 { mismatches.append("end") }
        if let allDay = changes.isAllDay, saved.isAllDay != allDay { mismatches.append("allDay") }
        if changes.clearLocation, saved.location != nil { mismatches.append("location") }
        if let location = changes.location, saved.location?.title != location.title { mismatches.append("location") }
        if let notes = changes.notes, (saved.notes ?? "") != notes { mismatches.append("notes") }
        if let url = changes.url, (saved.url ?? "") != url { mismatches.append("url") }
        if let availability = changes.availability, saved.availability != availability {
            mismatches.append("availability")
        }
        if let travel = changes.travelTimeSeconds, (saved.travelTimeSeconds ?? 0) != travel {
            mismatches.append("travelTime")
        }
        if let alerts = changes.alerts, !AlertSpec.same(saved.alerts.map(\.spec), alerts) {
            mismatches.append("alerts")
        }
        if let recurrence = changes.recurrence, saved.recurrence?.rrule != recurrence?.rrule {
            mismatches.append("repeat")
        }
        let emails = Set(saved.attendees.compactMap { $0.email?.lowercased() })
        if !changes.invite.allSatisfy({ emails.contains($0.email.lowercased()) })
            || changes.uninvite.contains(where: { emails.contains($0.lowercased()) })
        {
            mismatches.append("attendees")
        }
        guard mismatches.isEmpty else {
            throw PlatformError.saveFailed(
                "Event \(saved.id) did not read back as written (\(mismatches.joined(separator: ", "))); inspect it before retrying."
            )
        }
    }
}

extension CalendarAlertSnapshot {
    public var spec: AlertSpec {
        if let absoluteDate { return .at(absoluteDate) }
        return .before(minutes: Int((-(relativeOffsetSeconds ?? 0) / 60).rounded()))
    }
}

extension AlertSpec {
    static func same(_ lhs: [AlertSpec], _ rhs: [AlertSpec]) -> Bool {
        func key(_ spec: AlertSpec) -> String {
            switch spec {
            case .before(let minutes): "b\(minutes)"
            case .at(let date): "a\(Int(date.timeIntervalSince1970))"
            }
        }
        return lhs.map(key).sorted() == rhs.map(key).sorted()
    }
}
