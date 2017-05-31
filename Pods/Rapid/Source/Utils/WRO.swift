//
//  WRO.swift
//  Lavendr
//
//  Created by Jan Schwarz on 04/08/16.
//  Copyright © 2016 STRV. All rights reserved.
//

import Foundation

/// Wrapper for weak reference
class WRO<T: AnyObject>: Equatable where T: Hashable {
    weak fileprivate(set) var object: T?
    
    init(object: T?) {
        self.object = object
    }
}

extension WRO: Hashable {
    
    var hashValue: Int {
        return object?.hashValue ?? Int.min
    }
}

func == <T>(lhs: WRO<T>, rhs: WRO<T>) -> Bool {
    if lhs.object == rhs.object {
        return true
    }
    
    return false
}
