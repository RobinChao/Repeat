import Foundation

typealias RepeatClosure        = () -> ()
typealias RepeatClosureWithRet = () -> Repeat.Result

typealias RepeatSubscriberId   = UInt


class Repeat {
    enum Result {
        case Stop
        case Repeat
        case RepeatAfter(NSTimeInterval)
    }
    
    private struct SubscriberInfo {
        let closure: RepeatClosureWithRet
        var timeInterval: NSTimeInterval
    }
    
    private static let sharedInstance = Repeat()
    
    private static var subscribers: [RepeatSubscriberId: SubscriberInfo] = [:]
    
    private static var _nextSubscriberId: RepeatSubscriberId = 0
    private static var nextSubscriberId: RepeatSubscriberId {
        let id = _nextSubscriberId
        _nextSubscriberId += 1
        return id
    }
    
    
    // Execute a closure once
     
    // - Parameters:
    // - after: The timeInterval in seconds after which the closure is executed
    // - closure: The closure to execute
     
    // - Returns: Id which can be used to invalidate execution of the closure
    
    static func once(after timeInterval: NSTimeInterval, closure: RepeatClosure) -> RepeatSubscriberId {
        let closureWithRet: RepeatClosureWithRet = {
            closure()
            return .Stop
        }
        return Repeat.dispatch(timeInterval, closure: closureWithRet)
    }
    
    
    // Execute a closure repeatedly
     
    // - Parameters:
    // - seconds: The timeInterval in seconds after which the closure is executed
    // - closure: The closure to execute
     
    // - Returns: Id which can be used to invalidate execution of the closure

    static func every(seconds timeInterval: NSTimeInterval, closure: RepeatClosure) -> RepeatSubscriberId {
        let closureWithRet: RepeatClosureWithRet = {
            closure()
            return .Repeat
        }
        return Repeat.dispatch(timeInterval, closure: closureWithRet)
    }
    
    
    // Execute a closure after a desired delay. The closure's return param - to be provided by the client - will control whether the closure repeats (with the same or a different delay) or stops.
     
    // - Parameters:
    // - seconds: The timeInterval in seconds after which the closure is executed
    // - closure: The closure to execute
     
    // - Returns: Id which can be used to invalidate execution of the closure

    static func after(seconds timeInterval: NSTimeInterval, closure: RepeatClosureWithRet) -> RepeatSubscriberId {
        return Repeat.dispatch(timeInterval, closure: closure)
    }
    
    
    // Internal function which does the subscription and scheduling of the closures
     
    // - Parameters:
    // - timeInterval: TimeInterval (in seconds) until execution of closure
    // - closure: Closure to execute, should return RepeatResult
     
    // - Returns: Id which can be used to invalidate execution of the closure
    
    static private func dispatch(timeInterval: NSTimeInterval, closure: RepeatClosureWithRet) -> RepeatSubscriberId {
        assert(timeInterval > 0, "Expecting intervalSecs to be > 0, not \(timeInterval)")
        
        // thread safety
        objc_sync_enter(Repeat.sharedInstance)
        defer { objc_sync_exit(Repeat.sharedInstance) }
        
        // setup info for the repeat request
        let id = Repeat.nextSubscriberId
        Repeat.subscribers[id] = SubscriberInfo(closure: closure, timeInterval: timeInterval)
        
        // call the actual dispatch
        Repeat.dispatch(subscriberId: id, timeInterval: timeInterval)
        
        return id
    }
    
    
    // Internal function which does the scheduling of the closures
     
    // - Parameters:
    // - subscriberId: SubscribedId to dispatch for
    // - timeInterval: time until the next desired callback. Could be looked up via `subscriberId`, but 'unrolled' to avoid the unnecessary dictionary lookup, as both call sites (of this function) have it readily available.
    
    static private func dispatch(subscriberId subscriberId: RepeatSubscriberId, timeInterval: NSTimeInterval) {
        assert(Repeat.subscribers.keys.contains(subscriberId), "Invalid subscriberId \(subscriberId)")
        assert(timeInterval > 0, "Expecting intervalSecs to be > 0, not \(timeInterval)")
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(NSTimeInterval(NSEC_PER_SEC) * timeInterval)), dispatch_get_main_queue()) {
            Repeat.sharedInstance.timerCallback(subscriberId)
        }
    }
    
    
    // Invalidates closure execution for the given subscriberId
     
    // - Parameters:
    // - id: SubscriberId to cancel execution for
     
    // - Returns: Whether a subscriber was found and invalidated
    
    static func invalidate(id: RepeatSubscriberId) -> Bool {
        objc_sync_enter(Repeat.sharedInstance)
        defer { objc_sync_exit(Repeat.sharedInstance) }
        
        return Repeat.subscribers.removeValueForKey(id) != nil
    }
    
    
    // Invalidates closure execution for the given subscribers
     
    // - Parameters:
    // - ids: SubscriberIds to invalidate
     
    // - Returns: List of booleans which indicate whether each given subscriber was found and invalidated
    
    static func invalidate(ids: [RepeatSubscriberId]) -> [Bool] {
        guard !ids.isEmpty else { return [] }
        
        objc_sync_enter(Repeat.sharedInstance)
        defer { objc_sync_exit(Repeat.sharedInstance) }
        
        return ids.map { Repeat.subscribers.removeValueForKey($0) != nil }
    }
    
    
    // Internal function which processes the timer callbacks
     
    // - Parameters:
    // - timer: Timer which triggered
    
    private func timerCallback(subscriberId: RepeatSubscriberId) {
        objc_sync_enter(Repeat.sharedInstance)
        defer { objc_sync_exit(Repeat.sharedInstance) }
        
        // if we no longer have a record of the subscriber, assume it was invalidated and return (without scheduling any further callbacks for that subscriber)
        guard let info = Repeat.subscribers[subscriberId] else { return }
        
        let result = info.closure()
        
        // the client may have just invalidated us in the above closure - if so, don't attempt to dispatch another callback
        guard Repeat.subscribers.keys.contains(subscriberId) else { return }
        
        switch result {
        case .Stop:
            Repeat.subscribers.removeValueForKey(subscriberId)
        case .Repeat:
            Repeat.dispatch(subscriberId: subscriberId, timeInterval: info.timeInterval)
        case .RepeatAfter(let interval):
            assert(interval > 0, "Expecting interval to be > 0, not \(interval)")
            Repeat.subscribers[subscriberId] = SubscriberInfo(closure: info.closure, timeInterval: interval)
            
            Repeat.dispatch(subscriberId: subscriberId, timeInterval: interval)
        }
    }
}


extension RepeatSubscriberId {
    
    // Invalidates closure execution for this subscriber.
     
    // Instead of calling `Repeat.invalidate(subscriberId)`, this convenience extension lets us call `subscriberId.invalidate()`. Note that due to the typealias of `RepeatSubscriberId` to `UInt`, this pollutes UInt's 'namespace' so that you can do `UInt(0).invalidate()` and it compiles (though it is obviously nonsensical).
     
    // - Returns: Whether the subscriber was found and invalidated successfully
    
    func invalidate() -> Bool {
        return Repeat.invalidate(self)
    }
}