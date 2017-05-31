//
//  RapidAuthorization.swift
//  Rapid
//
//  Created by Jan on 20/04/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

/// Rapid authorization
public struct RapidAuthorization {
    
    /// Authorization token
    public let token: String
    
    init(token: String) {
        self.token = token
    }
}
