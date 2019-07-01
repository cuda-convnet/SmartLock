//
//  KeysViewController.swift
//  SmartLock
//
//  Created by Alsey Coleman Miller on 6/30/19.
//  Copyright © 2019 ColemanCDA. All rights reserved.
//

import Foundation
import Bluetooth
import GATT
import CoreLock

#if os(iOS)
import UIKit
import DarwinGATT
import JGProgressHUD
#endif

final class KeysViewController: UITableViewController {
    
    // MARK: - Properties
    
    private var items = [Item]() {
        didSet { configureView() }
    }
    
    private var locksObserver: Int?
    
    // MARK: - Loading
    
    deinit {
        
        if let observer = self.locksObserver {
            Store.shared.locks.remove(observer: observer)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // setup table view
        tableView.register(LockTableViewCell.nib, forCellReuseIdentifier: LockTableViewCell.reuseIdentifier)
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 60
        
        // load data
        locksObserver = Store.shared.locks.observe { [unowned self] in
            self.reloadData($0)
        }
        
        reloadData()
    }
    
    // MARK: - Methods
    
    private subscript (indexPath: IndexPath) -> Item {
        return items[indexPath.row]
    }
    
    private func reloadData(_ locks: [UUID: LockCache] = Store.shared.locks.value) {
        
        self.items = locks
            .lazy
            .map { Item(identifier: $0.key, cache: $0.value) }
            .sorted(by: { $0.identifier.description < $1.identifier.description })
    }
    
    private func configureView() {
        
        self.tableView.reloadData()
    }
    
    private func stateChanged(_ state: DarwinBluetoothState) {
        
        mainQueue {
            self.tableView.setEditing(false, animated: true)
        }
    }
    
    private func configure(cell: LockTableViewCell, at indexPath: IndexPath) {
        
        let item = self[indexPath]
        
        let permissionImage: UIImage
        let permissionText: String
        
        switch item.cache.key.permission {
        case .owner:
            permissionImage = #imageLiteral(resourceName: "permissionBadgeOwner")
            permissionText = "Owner"
        case .admin:
            permissionImage = #imageLiteral(resourceName: "permissionBadgeAdmin")
            permissionText = "Admin"
        case .anytime:
            permissionImage = #imageLiteral(resourceName: "permissionBadgeAnytime")
            permissionText = "Anytime"
        case .scheduled:
            permissionImage = #imageLiteral(resourceName: "permissionBadgeScheduled")
            permissionText = "Scheduled" // FIXME: Localized Schedule text
        }
        
        cell.lockTitleLabel.text = item.cache.name
        cell.lockDetailLabel.text = permissionText
        cell.lockImageView.image = permissionImage
        cell.activityIndicatorView.isHidden = true
        cell.lockImageView.isHidden = false
    }
    
    private func didSelect(_ item: Item) {
        
        
    }
    
    // MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: LockTableViewCell.reuseIdentifier, for: indexPath) as! LockTableViewCell
        
        // configure cell
        configure(cell: cell, at: indexPath)
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        let item = self[indexPath]
        didSelect(item)
    }
}

// MARK: - Supporting Types

private extension KeysViewController {
    
    struct Item {
        let identifier: UUID
        let cache: LockCache
    }
}
