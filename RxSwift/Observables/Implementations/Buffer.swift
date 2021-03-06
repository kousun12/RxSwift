//
//  Buffer.swift
//  Rx
//
//  Created by Krunoslav Zaher on 9/13/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

class BufferTimeCount<Element, S: SchedulerType> : Producer<[Element]> {
    
    private let _timeSpan: S.TimeInterval
    private let _count: Int
    private let _scheduler: S
    private let _source: Observable<Element>
    
    init(source: Observable<Element>, timeSpan: S.TimeInterval, count: Int, scheduler: S) {
        _source = source
        _timeSpan = timeSpan
        _count = count
        _scheduler = scheduler
    }
    
    override func run<O : ObserverType where O.E == [Element]>(observer: O) -> Disposable {
        let sink = BufferTimeCountSink(parent: self, observer: observer)
        sink.disposable = sink.run()
        return sink
    }
}

class BufferTimeCountSink<S: SchedulerType, Element, O: ObserverType where O.E == [Element]>
    : Sink<O>
    , LockOwnerType
    , ObserverType
    , SynchronizedOnType {
    typealias Parent = BufferTimeCount<Element, S>
    typealias E = Element
    
    private let _parent: Parent
    
    let _lock = NSRecursiveLock()
    
    // state
    private let _timerD = SerialDisposable()
    private var _buffer = [Element]()
    private var _windowID = 0
    
    init(parent: Parent, observer: O) {
        _parent = parent
        super.init(observer: observer)
    }
 
    func run() -> Disposable {
        createTimer(_windowID)
        return StableCompositeDisposable.create(_timerD, _parent._source.subscribe(self))
    }
    
    func startNewWindowAndSendCurrentOne() {
        _windowID = _windowID &+ 1
        let windowID = _windowID
        
        let buffer = _buffer
        _buffer = []
        forwardOn(.Next(buffer))
        
        createTimer(windowID)
    }
    
    func on(event: Event<E>) {
        synchronizedOn(event)
    }

    func _synchronized_on(event: Event<E>) {
        switch event {
        case .Next(let element):
            _buffer.append(element)
            
            if _buffer.count == _parent._count {
                startNewWindowAndSendCurrentOne()
            }
            
        case .Error(let error):
            _buffer = []
            forwardOn(.Error(error))
            dispose()
        case .Completed:
            forwardOn(.Next(_buffer))
            forwardOn(.Completed)
            dispose()
        }
    }
    
    func createTimer(windowID: Int) {
        if _timerD.disposed {
            return
        }
        
        if _windowID != windowID {
            return
        }
        
        _timerD.disposable = _parent._scheduler.scheduleRelative(windowID, dueTime: _parent._timeSpan) { previousWindowID in
            self._lock.performLocked {
                if previousWindowID != self._windowID {
                    return
                }
             
                self.startNewWindowAndSendCurrentOne()
            }
            
            return NopDisposable.instance
        }
    }
}