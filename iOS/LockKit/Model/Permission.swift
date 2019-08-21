//
//  Permission.swift
//  LockKit
//
//  Created by Alsey Coleman Miller on 8/21/19.
//  Copyright © 2019 ColemanCDA. All rights reserved.
//

import Foundation
import UIKit
import CoreLock

public extension UIImage {
    
    convenience init(permission: Permission) {
        
        self.init(permissionType: permission.type)
    }
    
    convenience init(permissionType: PermissionType) {
        
        let imageName: String
        switch permissionType {
        case .owner:
            imageName = "permissionBadgeOwner"
        case .admin:
            imageName = "permissionBadgeAdmin"
        case .anytime:
            imageName = "permissionBadgeAnytime"
        case .scheduled:
            imageName = "permissionBadgeScheduled"
        }
        
        self.init(named: imageName, in: .lockKit, compatibleWith: nil)!
    }
}

public extension PermissionType {
    
    var localizedText: String {
        
        switch self {
        case .owner:
            return NSLocalizedString("Owner", comment: "Permission.Owner")
        case .admin:
            return NSLocalizedString("Admin", comment: "Permission.Admin")
        case .anytime:
            return NSLocalizedString("Anytime", comment: "Permission.Anytime")
        case .scheduled:
            return NSLocalizedString("Scheduled", comment: "Permission.Scheduled")
        }
    }
}

public extension Permission {
    
    var localizedText: String {
        
        switch self {
        case .owner, .admin, .anytime:
            return type.localizedText
        case let .scheduled(schedule):
            return schedule.localizedText
        }
    }
}

public extension Permission.Schedule {
    
    var localizedText: String {
        // FIXME: Localized schedule
        return NSLocalizedString("Scheduled", comment: "Permission.Scheduled")
    }
}
