//
//  ConfirmNewKeyEventManagedObject.swift
//  LockKit
//
//  Created by Alsey Coleman Miller on 9/6/19.
//  Copyright © 2019 ColemanCDA. All rights reserved.
//

import Foundation
import CoreData
import CoreLock

public final class ConfirmNewKeyEventManagedObject: EventManagedObject {
    
    internal convenience init(_ value: LockEvent.ConfirmNewKey, lock: LockManagedObject, context: NSManagedObjectContext) {
        
        self.init(context: context)
        self.identifier = value.identifier
        self.lock = lock
        self.date = value.date
        self.key = value.key
        self.newKey = value.newKey
    }
}

// MARK: - IdentifiableManagedObject

extension ConfirmNewKeyEventManagedObject: IdentifiableManagedObject { }

// MARK: - Fetch

public extension ConfirmNewKeyEventManagedObject {
    
    /// Fetch the removed key specified by the event.
    func createKeyEvent(in context: NSManagedObjectContext) throws -> CreateNewKeyEventManagedObject? {
        
        guard let newKey = self.newKey else {
            assertionFailure("Missing new key value")
            return nil
        }
        
        let fetchRequest = NSFetchRequest<CreateNewKeyEventManagedObject>()
        fetchRequest.entity = CreateNewKeyEventManagedObject.entity()
        fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(CreateNewKeyEventManagedObject.newKey), newKey as NSUUID)
        fetchRequest.fetchLimit = 1
        fetchRequest.includesSubentities = true
        fetchRequest.returnsObjectsAsFaults = false
        return try context.fetch(fetchRequest).first
    }
}
