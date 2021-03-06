//
//  Unlock.swift
//  SmartLock
//
//  Created by Alsey Coleman Miller on 8/19/19.
//  Copyright © 2019 ColemanCDA. All rights reserved.
//

import Foundation
import UIKit
import CoreLock
import Intents

public extension ActivityIndicatorViewController where Self: UIViewController {
    
    func unlock(lock identifier: UUID, action: UnlockAction = .default, scanDuration: TimeInterval = 2.0) {
        
        log("Unlock \(identifier)")
        
        performActivity(queue: DispatchQueue.bluetooth, {
            guard let lockPeripheral = try Store.shared.device(for: identifier, scanDuration: scanDuration)
                else { throw LockError.notInRange(lock: identifier) }
            try Store.shared.unlock(lockPeripheral, action: action)
        }, completion: { (viewController, _) in
            log("Successfully unlocked lock \"\(identifier)\"")
        })
    }
    
    func unlock(lock: LockPeripheral<NativeCentral>, action: UnlockAction = .default) {
        performActivity(queue: .bluetooth, { try Store.shared.unlock(lock, action: action) })
    }
}

public extension UIViewController {
    
    /// Donate Siri Shortcut to unlock the specified lock.
    ///
    /// - Note: Prior to iOS 12 this method sets the current user activity.
    func donateUnlockIntent(for lock: UUID) {
        #if targetEnvironment(macCatalyst)
        #else
        guard let lockCache = Store.shared[lock: lock] else {
            assertionFailure("Invalid lock \(lock)")
            return
        }
        
        if #available(iOS 12, iOSApplicationExtension 12.0, *) {
            let intent = UnlockIntent(identifier: lock, cache: lockCache)
            let interaction = INInteraction(intent: intent, response: nil)
            interaction.donate { error in
                if let error = error {
                    log("⚠️ Donating intent failed with error \(error.localizedDescription)")
                }
            }
        } else {
            self.userActivity?.resignCurrent()
            self.userActivity = NSUserActivity(.action(.unlock(lock)))
            self.userActivity?.becomeCurrent()
        }
        #endif
    }
}
