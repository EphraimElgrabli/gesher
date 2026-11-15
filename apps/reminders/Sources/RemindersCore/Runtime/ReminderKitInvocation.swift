import Foundation
import ObjCRuntimeSupport

extension ReminderKitRuntime {
    /// The implementation of `selectorName` on `target`, cast to a C function type, for
    /// signatures the shared shims do not cover. The selector is checked first; forwarded
    /// selectors resolve through the ObjC forwarding machinery.
    func implementation<Function>(_ target: AnyObject, _ selectorName: String, as type: Function.Type) throws -> (
        Selector, Function
    ) {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector), let cls = object_getClass(target),
            let imp = class_getMethodImplementation(cls, selector)
        else {
            throw ReminderCLIError.missingSelector(
                className: String(describing: Swift.type(of: target)), selector: selectorName)
        }
        return (selector, unsafeBitCast(imp, to: Function.self))
    }

    /// `- (void)selector:(nullable id)value`, allowing nil to clear a value.
    func sendVoidOptional(_ target: AnyObject, _ selectorName: String, _ value: AnyObject?) throws {
        typealias Setter = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        let (selector, call) = try implementation(target, selectorName, as: Setter.self)
        call(target, selector, value)
    }

    /// `- (id)selector:(id)first :(id)second` returning an object, allowing nil arguments.
    func sendObjectOptional(_ target: AnyObject, _ selectorName: String, _ first: AnyObject?, _ second: AnyObject?)
        throws -> AnyObject?
    {
        typealias Call = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?) -> AnyObject?
        let (selector, call) = try implementation(target, selectorName, as: Call.self)
        return call(target, selector, first, second)
    }

    /// `- (void)selector:(id)first :(id)second` (e.g. insertReminderChangeItem:beforeReminderChangeItem:).
    func sendVoidTwo(_ target: AnyObject, _ selectorName: String, _ first: AnyObject, _ second: AnyObject) throws {
        typealias Call = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> Void
        let (selector, call) = try implementation(target, selectorName, as: Call.self)
        call(target, selector, first, second)
    }

    /// `addRecurrenceRuleWithFrequency:interval:daysOfTheWeek:daysOfTheMonth:monthsOfTheYear:
    /// weeksOfTheYear:daysOfTheYear:setPositions:end:` on a reminder change item.
    func addRecurrenceRule(
        _ changeItem: AnyObject, frequency: Int, interval: Int, daysOfTheWeek: NSArray?, daysOfTheMonth: NSArray?,
        end: AnyObject?
    ) throws {
        typealias Call =
            @convention(c) (
                AnyObject, Selector, Int, Int, AnyObject?, AnyObject?, AnyObject?, AnyObject?, AnyObject?, AnyObject?,
                AnyObject?
            ) -> AnyObject?
        let (selector, call) = try implementation(
            changeItem,
            "addRecurrenceRuleWithFrequency:interval:daysOfTheWeek:daysOfTheMonth:monthsOfTheYear:weeksOfTheYear:daysOfTheYear:setPositions:end:",
            as: Call.self)
        _ = call(changeItem, selector, frequency, interval, daysOfTheWeek, daysOfTheMonth, nil, nil, nil, nil, end)
    }

    /// `+ (instancetype)dayOfWeek:(NSInteger)day` on REMRecurrenceDayOfWeek.
    func recurrenceDayOfWeek(_ day: Int) throws -> AnyObject {
        guard let cls = NSClassFromString("REMRecurrenceDayOfWeek") else {
            throw ReminderCLIError.missingClass("REMRecurrenceDayOfWeek")
        }
        typealias Call = @convention(c) (AnyObject, Selector, Int) -> AnyObject?
        let (selector, call) = try implementation(cls as AnyObject, "dayOfWeek:", as: Call.self)
        guard let value = call(cls as AnyObject, selector, day) else {
            throw ReminderCLIError.fetchFailed("REMRecurrenceDayOfWeek rejected day \(day).")
        }
        return value
    }

    /// `- (instancetype)initWithUnit:(NSInteger)unit count:(NSInteger)count` on REMDueDateDeltaInterval.
    func dueDateDelta(unit: Int, count: Int) throws -> AnyObject {
        guard let cls = NSClassFromString("REMDueDateDeltaInterval") as? NSObject.Type,
            let allocated = ObjCAlloc(cls) as AnyObject?
        else { throw ReminderCLIError.missingClass("REMDueDateDeltaInterval") }
        typealias Call = @convention(c) (AnyObject, Selector, Int, Int) -> AnyObject?
        let (selector, call) = try implementation(allocated, "initWithUnit:count:", as: Call.self)
        guard let value = call(allocated, selector, unit, count) else {
            throw ReminderCLIError.fetchFailed("REMDueDateDeltaInterval rejected \(count) of unit \(unit).")
        }
        return value
    }

    /// Allocates `className` and calls a one-object initializer.
    func make(_ className: String, _ initializer: String, _ argument: AnyObject) throws -> AnyObject {
        guard let cls = NSClassFromString(className) as? NSObject.Type, let allocated = ObjCAlloc(cls) as AnyObject?
        else { throw ReminderCLIError.missingClass(className) }
        let selector = NSSelectorFromString(initializer)
        guard allocated.responds(to: selector) else {
            throw ReminderCLIError.missingSelector(className: className, selector: initializer)
        }
        guard let value = ObjCSendInitId(allocated, selector, argument) as AnyObject? else {
            throw ReminderCLIError.fetchFailed("\(className).\(initializer) returned nil.")
        }
        return value
    }
}

extension ReminderKitRuntime {
    /// `- (id)selector:(id)first :(id)second error:(NSError **)error`.
    func sendObjectError(_ target: AnyObject, _ selectorName: String, _ first: AnyObject, _ second: AnyObject) throws
        -> AnyObject?
    {
        typealias Call =
            @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>?)
            -> AnyObject?
        let (selector, call) = try implementation(target, selectorName, as: Call.self)
        var error: NSError?
        let result = call(target, selector, first, second, &error)
        if let error { throw ReminderCLIError.fetchFailed(error.localizedDescription) }
        return result
    }

    /// Fetch options that also load "Early Reminder" (due-date delta) alerts.
    func fetchOptionsWithEarlyAlerts() -> AnyObject? {
        guard let cls = NSClassFromString("REMReminderFetchOptions") else { return nil }
        return objectValue(from: cls as AnyObject, selectors: ["fetchOptionsIncludingDueDateDeltaAlerts"])
    }
}
