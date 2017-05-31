//
//  NewMessageViewController.swift
//  RapidDemo
//
//  Created by Jan on 31/05/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import UIKit
import Rapid

class NewMessageViewController: UIViewController {

    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var doneButton: UIBarButtonItem!
    
    var username: String!
    var message: Message?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        
        textView.becomeFirstResponder()
    }
    
    @IBAction func send(_ sender: Any) {
        sendMessage()
        navigationController?.popViewController(animated: true)
    }

    @IBAction func cancel(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }
}

extension NewMessageViewController: UITextViewDelegate {
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let text = ((textView.text ?? "") as NSString).replacingCharacters(in: range, with: text)
        
        doneButton.isEnabled = !text.isEmpty
        
        return true
    }
}

fileprivate extension NewMessageViewController {
    
    func setupUI() {
        doneButton.isEnabled = message != nil
        textView.text = message?.text
    }
    
    func sendMessage() {
    }
}
