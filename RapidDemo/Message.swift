//
//  Message.swift
//  RapidDemo
//
//  Created by Jan on 31/05/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation
import Rapid

struct Message {
    
    let id: String
    let username: String
    let text: String
    
    init?(withDocument document: RapidDocument) {
        guard let value = document.value else {
            return nil
        }
        
        guard let username = value[Message.usernamePropertyName] as? String else {
            return nil
        }
        
        guard let text = value[Message.textPropertyName] as? String else {
            return nil
        }
        
        self.id = document.id
        self.username = username
        self.text = text
    }
}

extension Message {
    
    static let usernamePropertyName = "username"
    static let textPropertyName = "text"
}
