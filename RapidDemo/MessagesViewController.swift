//
//  MessagesViewController.swift
//  RapidDemo
//
//  Created by Jan on 31/05/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import UIKit
import Rapid

class MessagesViewController: UIViewController {

    @IBOutlet weak var usernameTextField: UITextField!
    @IBOutlet weak var tableView: UITableView!
    
    @IBOutlet weak var plusButton: UIBarButtonItem!
    
    fileprivate var messages: [Message] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        subscribe()
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let controller = segue.destination as? NewMessageViewController {
            controller.username = usernameTextField.text
        }
    }
}

extension MessagesViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell", for: indexPath) as! MessageCell
        
        let message = messages[indexPath.row]
        cell.configure(withMessage: message, myUsername: usernameTextField.text ?? "")
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
//        let message = messages[indexPath.row]
//        if !(usernameTextField.text?.isEmpty ?? true) {
//            presentMessageController(withMessge: message)
//        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return false
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        // TODO: Delete
    }
}

extension MessagesViewController: UITextFieldDelegate {
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let text = ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string)
        
        plusButton.isEnabled = !text.isEmpty
        
        return true
    }
}

fileprivate extension MessagesViewController {
    
    func setupUI() {
        plusButton.isEnabled = false
        
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 60
    }
    
    func presentMessageController(withMessge message: Message) {
        let controller = self.storyboard?.instantiateViewController(withIdentifier: "NewMessageViewController") as! NewMessageViewController
        
        controller.username = usernameTextField.text
        controller.message = message
        
        navigationController?.pushViewController(controller, animated: true)
    }
    
    func subscribe() {
        // TODO: Subscribe
    }
}
