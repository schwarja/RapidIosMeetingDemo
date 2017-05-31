//
//  MessageCell.swift
//  RapidDemo
//
//  Created by Jan on 31/05/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import UIKit

class MessageCell: UITableViewCell {
    
    @IBOutlet weak var usernameLabel: UILabel!
    @IBOutlet weak var messageLabel: UILabel!

    func configure(withMessage message: Message, myUsername: String) {
        usernameLabel.textColor = message.username == myUsername ? .red : .blue
        usernameLabel.text = message.username
        messageLabel.text = message.text
    }

}
