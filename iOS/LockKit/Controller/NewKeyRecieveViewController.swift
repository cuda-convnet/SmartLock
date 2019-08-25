//
//  NewKeyRecieveViewController.swift
//  Lock
//
//  Created by Alsey Coleman Miller on 7/11/16.
//  Copyright © 2016 ColemanCDA. All rights reserved.
//

import Foundation
import UIKit
import Bluetooth
import GATT
import CoreLock
import JGProgressHUD

public final class NewKeyRecieveViewController: UITableViewController, ActivityIndicatorViewController {
    
    // MARK: - IB Outlets
    
    @IBOutlet private(set) weak var permissionView: PermissionIconView!
    @IBOutlet private(set) weak var permissionLabel: UILabel!
    @IBOutlet private(set) weak var lockLabel: UILabel!
    
    // MARK: - Properties
    
    public private(set) var newKey: NewKey.Invitation!
        
    public lazy var progressHUD: JGProgressHUD = .currentStyle(for: self)
    
    // MARK: - Loading
    
    public static func fromStoryboard(with newKey: NewKey.Invitation) -> NewKeyRecieveViewController {
        guard let viewController = R.storyboard.newKeyInvitation.newKeyRecieveViewController()
            else { fatalError("Could not load \(self) from storyboard") }
        viewController.newKey = newKey
        return viewController
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        assert(newKey != nil)
        
        self.tableView.tableFooterView = UIView()
        
        configureView()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        view.bringSubviewToFront(progressHUD)
    }
    
    // MARK: - Actions
    
    @IBAction func cancel(_ sender: UIBarItem) {
        
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func save(_ sender: UIBarItem) {
        
        let newKeyInvitation = self.newKey!
        sender.isEnabled = false
        let keyData = KeyData()
        showProgressHUD()
        
        async { [weak self] in
            
            guard let controller = self else { return }
            
            do {
                
                // scan lock is neccesary
                if Store.shared[peripheral: newKeyInvitation.lock] == nil {
                    try Store.shared.scan(duration: 3)
                }
                
                guard let peripheral = Store.shared[peripheral: newKeyInvitation.lock],
                    let information = Store.shared.lockInformation.value[peripheral]
                    else { throw CentralError.unknownPeripheral }
                
                // recieve new key
                let credentials = KeyCredentials(
                    identifier: newKeyInvitation.key.identifier,
                    secret: newKeyInvitation.secret
                )
                try LockManager.shared.confirmKey(.init(secret: keyData),
                                                  for: peripheral,
                                                  with: credentials)
                
                // update UI
                mainQueue {
                    
                    // save to cache
                    
                    let lockCache = LockCache(
                        key: Key(
                            identifier: newKeyInvitation.key.identifier,
                            name: newKeyInvitation.key.name,
                            created: newKeyInvitation.key.created,
                            permission: newKeyInvitation.key.permission
                        ),
                        name: "Lock",
                        information: .init(characteristic: information)
                    )
                    
                    Store.shared[lock: newKeyInvitation.lock] = lockCache
                    Store.shared[key: newKeyInvitation.key.identifier] = keyData
                    controller.dismissProgressHUD()
                    controller.dismiss(animated: true, completion: nil)
                }
            }
            
            catch {
                
                mainQueue {
                    
                    controller.dismissProgressHUD(animated: false)
                    controller.showErrorAlert("\(error)", okHandler: {
                        controller.dismiss(animated: true, completion: nil)
                    })
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func configureView() {
        
        self.navigationItem.title = newKey.key.name
        let permission = newKey.key.permission
        self.lockLabel.text = newKey.lock.rawValue
        self.permissionView.permission = permission.type
        self.permissionLabel.text = permission.localizedText
    }
}

public extension UIViewController {
    
    @discardableResult
    func open(newKey: NewKey.Invitation) -> Bool {
        
        // only one key per lock
        guard Store.shared[lock: newKey.lock] == nil else {
            self.showErrorAlert("You already have a key for lock \(newKey.lock).")
            return false
        }
        
        let newKeyViewController = NewKeyRecieveViewController.fromStoryboard(with: newKey)
        let navigationController = UINavigationController(rootViewController: newKeyViewController)
        present(navigationController, animated: true, completion: nil)
        return true
    }
}
