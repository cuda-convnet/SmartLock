//
//  NewKeySelectPermissionViewController.swift
//  Lock
//
//  Created by Alsey Coleman Miller on 4/26/16.
//  Copyright © 2016 ColemanCDA. All rights reserved.
//

import Foundation
import UIKit
import CoreLock
import Foundation
import JGProgressHUD

public final class NewKeySelectPermissionViewController: UITableViewController, NewKeyViewController {
    
    // MARK: - Properties
    
    public var completion: ((Bool) -> ())?
    
    public var lockIdentifier: UUID!
    
    public let progressHUD = JGProgressHUD(style: .dark)
    
    private let permissionTypes: [PermissionType] = [.admin, .anytime /*, .scheduled */ ]
    
    // MARK: - Loading
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        // set user activity
        userActivity = NSUserActivity(.action(.shareKey(lockIdentifier)))
        
        // setup table view
        self.tableView.estimatedRowHeight = 100
        self.tableView.rowHeight = UITableView.automaticDimension
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        view.bringSubviewToFront(progressHUD)
    }
    
    // MARK: - Actions
    
    @IBAction func cancel(_ sender: AnyObject?) {
        
        let completion = self.completion // for ARC
        
        self.dismiss(animated: true) { completion?(false) }
    }
    
    // MARK: - Methods
    
    private func description(for permissionType: PermissionType) -> String {
        
        switch permissionType {
        case .admin:
            return "Admin keys have unlimited access, and can create new keys."
        case .anytime:
            return "Anytime keys have unlimited access, but cannot create new keys."
        case .scheduled:
            return "Scheduled keys have limited access during specified hours, and expire at a certain date. New keys cannot be created from this key"
        case .owner:
            assertionFailure("Cannot create owner keys")
            return "Owner keys are created at setup."
        }
    }
    
    private func configure(cell: PermissionTypeTableViewCell, at indexPath: IndexPath) {
        
        let permissionType = permissionTypes[indexPath.row]
        
        cell.permissionImageView.image = UIImage(permissionType: permissionType)
        cell.permissionTypeLabel.text = permissionType.localizedText
        cell.permissionDescriptionLabel.text = description(for: permissionType)
    }
    
    // MARK: - UITableViewDataSource
    
    public override func numberOfSections(in tableView: UITableView) -> Int {
        
        return 1
    }
    
    public override func tableView(_ tableView: UITableView, numberOfRowsInSection: Int) -> Int {
        
        return permissionTypes.count
    }
    
    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: PermissionTypeTableViewCell.resuseIdentifier, for: indexPath) as! PermissionTypeTableViewCell
        configure(cell: cell, at: indexPath)
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        tableView.deselectRow(at: indexPath, animated: true)
        
        let cell = tableView.cellForRow(at: indexPath) as! PermissionTypeTableViewCell
        
        let selectedType = permissionTypes[indexPath.row]
        
        switch selectedType {
        case .owner:
            fatalError("Cannot create owner keys")
        case .admin:
            newKey(permission: .admin, sender: .view(cell.permissionImageView)) { [unowned self] _ in
                self.completion?(true)
            }
        case .anytime:
            newKey(permission: .anytime, sender: .view(cell.permissionImageView)) { [unowned self] _ in
                self.completion?(true)
            }
        case .scheduled:
            fatalError("Not implemented")
        }
    }
}

public extension UIViewController {
    
    func shareKey(lock identifier: UUID) {
        
        let navigationController = UIStoryboard(name: "NewKey", bundle: .lockKit).instantiateInitialViewController() as! UINavigationController
        
        let destinationViewController = navigationController.viewControllers.first! as! NewKeySelectPermissionViewController
        destinationViewController.lockIdentifier = identifier
        destinationViewController.completion = { _ in navigationController.dismiss(animated: true, completion: nil) }
        self.present(navigationController, animated: true, completion: nil)
    }
}

// MARK: - Supporting Types

public final class PermissionTypeTableViewCell: UITableViewCell {
    
    static let resuseIdentifier = "PermissionTypeTableViewCell"
    
    @IBOutlet weak var permissionImageView: UIImageView!
    
    @IBOutlet weak var permissionTypeLabel: UILabel!
    
    @IBOutlet weak var permissionDescriptionLabel: UILabel!
}