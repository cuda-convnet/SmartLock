//
//  iCloud.swift
//  LockKit
//
//  Created by Alsey Coleman Miller on 8/25/19.
//  Copyright © 2019 ColemanCDA. All rights reserved.
//

import Foundation
import CoreData
import CloudKit
import CloudKitCodable
import KeychainAccess
import CoreLock

public final class CloudStore {
    
    public static let shared = CloudStore()
    
    deinit {
        
        #if os(iOS)
        if let observer = keyValueStoreObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }
    
    private init() {
        
        #if os(iOS)
        // observe changes
        keyValueStoreObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self.keyValueStore,
            queue: nil,
            using: { [weak self] in self?.didChangeExternally($0) })
        #endif
    }
    
    // MARK: - Properties
    
    public var didChange: (() -> ())?
    
    private lazy var keychain = Keychain(service: .lockCloud, accessGroup: .lock).synchronizable(true)
    
    #if os(iOS)
    private lazy var keyValueStore: NSUbiquitousKeyValueStore = .default
    #endif
    
    private var keyValueStoreObserver: NSObjectProtocol?
    
    internal lazy var container: CKContainer = .lock
        
    // MARK: - Methods
    
    @discardableResult
    public func requestPermissions() throws -> CKContainer_Application_PermissionStatus {
        return try container.requestApplicationPermission([.userDiscoverability])
    }
    
    public func accountStatus() throws -> CKAccountStatus {
        return try container.accountStatus()
    }
    
    public func upload(applicationData: ApplicationData,
                       keys: [UUID: KeyData]) throws {
        
        // store lock private keys in iCloud keychain
        for (keyIdentifier, keyData) in keys {
            assert(applicationData[key: keyIdentifier] != nil, "Invalid key")
            try keychain.set(keyData.data, key: keyIdentifier.uuidString)
        }
        
        // update iCloud user
        var user = try CloudUser.fetch(in: container, database: .private)
        user.applicationData = .init(applicationData, user: user.id) // set new application data
        try upload(user)
        
        // inform via key value store
        didUpload(applicationData: applicationData)
    }
    
    public func upload(context: NSManagedObjectContext) throws {
        
        // upload all locks and keys]
        let locks = try LockManagedObject.fetch(in: context)
        for lockManagedObject in locks {
            guard let lock = CloudLock(managedObject: lockManagedObject) else {
                assertionFailure("Invalid \(lockManagedObject)")
                continue
            }
            try upload(lock)
            // upload events
            let events = ((lockManagedObject.events as? Set<EventManagedObject>) ?? [])
                .lazy
                .sorted(by: { $0.date! > $1.date! })
            for eventManagedObject in events {
                guard let event = LockEvent(managedObject: eventManagedObject)
                    .flatMap({ LockEvent.Cloud(event: $0, for: lock.id.rawValue) }) else {
                    assertionFailure("Invalid \(eventManagedObject)")
                    continue
                }
                if try container.privateCloudDatabase.fetch(record: event.cloudIdentifier.cloudRecordID) == nil {
                    let _ = try upload(event)
                } else {
                    break // don't upload older events
                }
            }
            // upload keys
            let keys = ((lockManagedObject.keys as? Set<KeyManagedObject>) ?? [])
                .lazy
                .sorted(by: { $0.created! > $1.created! })
            for managedObject in keys {
                guard let key = Key(managedObject: managedObject)
                    .flatMap({ Key.Cloud($0, lock: lock.id.rawValue) }) else {
                    assertionFailure("Invalid \(managedObject)")
                    continue
                }
                if try container.privateCloudDatabase.fetch(record: key.cloudIdentifier.cloudRecordID) == nil {
                    let _ = try upload(key)
                } else {
                    break // don't upload older events
                }
            }
            // upload new keys
            let newKeys = ((lockManagedObject.pendingKeys as? Set<NewKeyManagedObject>) ?? [])
                .lazy
                .sorted(by: { $0.created! > $1.created! })
            for managedObject in newKeys {
                guard let newKey = NewKey(managedObject: managedObject)
                    .flatMap({ NewKey.Cloud($0, lock: lock.id.rawValue) }) else {
                    assertionFailure("Invalid \(managedObject)")
                    continue
                }
                let existingRecord = try container.privateCloudDatabase.fetch(record: newKey.cloudIdentifier.cloudRecordID)
                if existingRecord == nil {
                    let _ = try upload(newKey)
                } else {
                    break // don't upload older events
                }
            }
        }
    }
    
    @discardableResult
    internal func upload <T: CloudKitEncodable> (_ encodable: T, database scope: CKDatabase.Scope = .private) throws -> CKRecord {
        
        let database = container.database(with: scope)
        let cloudEncoder = CloudKitEncoder(context: database)
        let operation = try cloudEncoder.encode(encodable)
        guard let record = operation.recordsToSave?.first
            else { fatalError() }
        assert(encodable.cloudIdentifier.cloudRecordID == record.recordID)
        assert(type(of: encodable.cloudIdentifier).cloudRecordType == record.recordType)
        operation.isAtomic = true
        operation.savePolicy = .changedKeys
        try database.modify(operation)
        return record
    }
    
    public func downloadApplicationData() throws -> (applicationData: ApplicationData, keys: [UUID: KeyData])? {
        
        // get iCloud user
        let user = try CloudUser.fetch(in: container, database: .private)
        guard let cloudData = user.applicationData
            else { return nil }
        guard let applicationData = ApplicationData(cloudData) else {
            #if DEBUG
            dump(cloudData)
            assertionFailure("Could not initialize from iCloud")
            #endif
            return nil
        }
        
        // download keys from keychain
        var keys = [UUID: KeyData](minimumCapacity: applicationData.locks.count)
        for key in applicationData.keys {
            guard let data = try keychain.getData(key.identifier.uuidString),
                let keyData = KeyData(data: data)
                else { throw Error.missingKeychainItem(key.identifier) }
            keys[key.identifier] = keyData
        }
        
        return (applicationData, keys)
    }
    
    private func didUpload(applicationData: ApplicationData) {
        
        #if os(iOS)
        // inform iCloud Key Value Store
        keyValueStore.set(applicationData.updated as NSDate, forKey: UbiquitousKey.updated.rawValue)
        keyValueStore.synchronize()
        #elseif os(watchOS)
        
        #endif
    }
    
    #if os(iOS)
    public func lastUpdated() -> Date? {
        
        keyValueStore.synchronize()
        return keyValueStore.object(forKey: UbiquitousKey.updated.rawValue) as? Date
    }
    #endif
    
    #if os(iOS)
    private func didChangeExternally(_ notification: Notification) {
        
        keyValueStore.synchronize()
        didChange?()
    }
    #endif
}

public extension CloudStore {
    
    /// CloudStore Error
    enum Error: Swift.Error {
        
        /// Could not import due to missing KeyChain item.
        case missingKeychainItem(UUID)
    }
}

private extension CloudStore {
    
    enum KeyChainKey: String {
        
        case applicationData = "com.colemancda.Lock.ApplicationData"
    }
}

private extension Keychain {
    
    func set(_ value: Data, key: CloudStore.KeyChainKey) throws {
        try set(value, key: key.rawValue)
    }
    
    func getData(_ key: CloudStore.KeyChainKey) throws -> Data? {
        return try getData(key.rawValue)
    }
}

private extension CloudStore {
    
    enum UbiquitousKey: String {
        
        case updated
    }
}

internal extension ApplicationData {
    
    /// Attempt to update with no conflicts.
    func update(with applicationData: ApplicationData) -> ApplicationData? {
        
        // must be originally the same application data
        guard self.identifier == applicationData.identifier,
            self.created == applicationData.created
            else { return nil }
        
        // if local copy is newer, should not be overwritten with older copy.
        guard self.locks != applicationData.locks else {
            // locks not changed
            if self.updated <= applicationData.updated {
                return applicationData
            } else {
                return self
            }
        }
        
        // if local copy is newer, should not be overwritten with older copy.
        guard self.keys != applicationData.keys else {
            // no keys changed, keep newer local copy
            if self.updated <= applicationData.updated {
                return applicationData
            } else {
                return self
            }
        }
        
        // overwrite with newer cloud data
        guard self.updated > applicationData.updated
            else { return applicationData }
        
        return nil
    }
}

public extension Store {
    
    #if os(iOS)
    func cloudDidChangeExternally() {
        
        if let lastUpdatedCloud = self.cloud.lastUpdated() {
            guard self.applicationData.updated != lastUpdatedCloud
                else { return }
        }
        
        log("☁️ iCloud changed externally")
        
        DispatchQueue.cloud.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.syncCloud(conflicts: { _ in
                    return nil
                })
            }
            catch { log("⚠️ Could not sync iCloud: \(error.localizedDescription)") }
        }
    }
    #endif
    
    func syncCloud(conflicts: (ApplicationData) -> Bool? = { _ in return nil }) throws {
        
        assert(Thread.isMainThread == false)
        
        // make sure iCloud is enabled
        guard preferences.isCloudBackupEnabled,
            try Store.shared.cloud.accountStatus() == .available
            else { return }
        
        // update from filesystem just in case
        loadCache()
        
        // download to CoreData
        try downloadCloudLocks()
        
        // local data should override remote
        updateCoreData()
        
        // upload from CoreData
        try uploadCloudLocks()
        
        // download and upload application data
        if try downloadCloudApplicationData(conflicts: conflicts) {
            try uploadCloudApplicationData()
        }
        
        // cache date last updated
        DispatchQueue.main.async { [weak self] in
            self?.preferences.lastCloudUpdate = Date()
        }
    }
    
    func uploadCloudLocks() throws {
        
        let context = persistentContainer.newBackgroundContext()
        try context.performErrorBlockAndWait { [unowned self] in
            try self.cloud.upload(context: context)
        }
    }
    
    func downloadCloudLocks() throws {
        
        var insertedEventsCount = 0
        var insertedKeysCount = 0
        var insertedNewKeysCount = 0
        
        defer {
            if insertedEventsCount > 0 {
                log("☁️ Fetched \(insertedEventsCount) events")
            }
            if insertedKeysCount > 0 {
                log("☁️ Fetched \(insertedKeysCount) keys")
            }
            if insertedNewKeysCount > 0 {
                log("☁️ Fetched \(insertedNewKeysCount) pending keys")
            }
        }
        
        let context = backgroundContext
        
        try cloud.fetchLocks { [weak self] (lock) in
            guard let self = self else { return false }
            
            // store in CoreData
            context.commit {
                let managedObject = try $0.insert(lock)
                // override name
                if let cache = self.locks.value[lock.id.rawValue] {
                    managedObject.name = cache.name
                }
            }
            
            // fetch events
            try self.cloud.fetchEvents(for: lock.id) { (cloudEvent) in
                guard let event = LockEvent(cloudEvent) else {
                    assertionFailure()
                    return true // more events, ignore invalid cloud value
                }
                // if already in CoreData, then stop
                guard try EventManagedObject.find(event.identifier, in: context) == nil
                    else { return false }
                // save event in CoreData
                context.commit {
                    try $0.insert(event, for: cloudEvent.lock.rawValue)
                }
                insertedEventsCount += 1
                return true
            }
            
            // fetch keys
            try self.cloud.fetchKeys(for: lock.id) { (cloudValue) in
                guard let value = Key(cloudValue) else {
                    assertionFailure()
                    return true // more values, ignore invalid cloud value
                }
                // if already in CoreData, then stop
                guard try context.find(identifier: value.identifier, type: KeyManagedObject.self) == nil
                    else { return false }
                // save value in CoreData
                context.commit {
                    try $0.insert(value, for: cloudValue.lock.rawValue)
                }
                insertedKeysCount += 1
                return true
            }
            
            // fetch new keys
            try self.cloud.fetchNewKeys(for: lock.id) { (cloudValue) in
                guard let value = NewKey(cloudValue) else {
                    assertionFailure()
                    return true // more values, ignore invalid cloud value
                }
                // if already in CoreData, then stop
                guard try context.find(identifier: value.identifier, type: NewKeyManagedObject.self) == nil
                    else { return false }
                // save value in CoreData
                context.commit {
                    try $0.insert(value, for: cloudValue.lock.rawValue)
                }
                insertedNewKeysCount += 1
                return true
            }
            
            return true
        }
    }
    
    @discardableResult
    func downloadCloudApplicationData(conflicts: (ApplicationData) -> Bool?) throws -> Bool {
        
        assert(Thread.isMainThread == false)
                
        guard let (cloudData, cloudKeys) = try cloud.downloadApplicationData() else {
            log("☁️ No data in iCloud")
            return true
        }
        
        // Import private keys
        var newKeysCount = 0
        for (identifier, keyData) in cloudKeys {
            if self[key: identifier] == nil {
                self[key: identifier] = keyData
                newKeysCount += 1
            }
        }
        if newKeysCount > 0 {
            log("☁️ Imported \(newKeysCount) keys from iCloud")
        }
        
        // Import application data
        let oldApplicationData = self.applicationData
        guard cloudData != oldApplicationData else {
            log("☁️ No new data from iCloud")
            return false
        }
        
        #if DEBUG
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        print("Cloud: \(cloudData.identifier) \(dateFormatter.string(from: cloudData.updated))")
        dump(cloudData)
        print("Local: \(oldApplicationData.identifier) \(dateFormatter.string(from: oldApplicationData.updated))")
        dump(oldApplicationData)
        #endif
        
        // attempt to overwrite
        if let newData = oldApplicationData.update(with: cloudData) {
            // write new application data
            self.applicationData = newData
            if newData != oldApplicationData {
                log("☁️ Updated application data from iCloud")
            } else {
                log("☁️ Keeping local data over iCloud")
            }
        } else if let shouldOverwrite = conflicts(cloudData) {
            // ask user to replace with conflicting data
            if shouldOverwrite {
                self.applicationData = cloudData
                log("☁️ Overriding application data from iCloud")
            } else {
                log("☁️ Discarding conflicting iCloud application data")
            }
        } else {
            log("☁️ Aborted iCloud download due to unresolved conflict")
            return false
        }
        // remove old keys
        var removedKeys = 0
        let newData = self.applicationData
        let newKeys = newData.keys.map { $0.identifier }
        let oldKeys = oldApplicationData.keys.map { $0.identifier }
        for oldKey in oldKeys {
            // old key no longer exists
            guard newKeys.contains(oldKey) == false
                else { continue }
            // remove from keychain
            self[key: oldKey] = nil
            removedKeys += 1
        }
        if removedKeys > 0 {
            log("☁️ Removed \(removedKeys) old keys from keychain")
        }
        log("☁️ Downloaded application data from iCloud")
        return true
    }
    
    func uploadCloudApplicationData() throws {
                
        let applicationData = self.applicationData
        
        // read from to keychain
        var keys = [UUID: KeyData]()
        for key in applicationData.keys {
            let keyData = self[key: key.identifier]
            keys[key.identifier] = keyData
        }
        
        // upload keychain and application data to iCloud
        try cloud.upload(applicationData: applicationData, keys: keys)
        
        log("☁️ Uploaded application data to iCloud")
    }
}

#if os(iOS)
import UIKit

public extension ActivityIndicatorViewController where Self: UIViewController {
    
    func syncCloud(showActivity: Bool) {
        
        assert(Thread.isMainThread)
        
        guard Store.shared.preferences.isCloudBackupEnabled else { return }
        
        performActivity(showActivity: showActivity, queue: .cloud, { [weak self] in
            try Store.shared.syncCloud(conflicts: { self?.resolveCloudSyncConflicts($0) })
        }, completion: { (viewController, _) in
            
        })
    }
}

public extension UIViewController {
    
    func syncCloud(completion: @escaping (Result<Void, Error>) -> ()) {
        
        assert(Thread.isMainThread)
        
        DispatchQueue.cloud.async { [weak self] in
            do {
                try Store.shared.syncCloud(conflicts: { [weak self] in
                    self?.resolveCloudSyncConflicts($0)
                })
                completion(.success(()))
            }
            catch { mainQueue { completion(.failure(error)) } }
        }
    }
    
    func syncCloud() {
        syncCloud {
            switch $0 {
            case let .failure(error):
                log("⚠️ Could not sync iCloud: \(error.localizedDescription)")
            case .success:
                break
            }
        }
    }
}

private extension UIViewController {
    
    func resolveCloudSyncConflicts(_ cloudData: ApplicationData) -> Bool? {
        
        assert(Thread.isMainThread == false)
        
        let semaphore = DispatchSemaphore(value: 0)
        var shouldOverwrite: Bool?
        var alertController: UIAlertController?
        mainQueue {
            
            let alert = UIAlertController(
                title: "Conflicting iCloud Data",
                message: "Overwrite from iCloud data?",
                preferredStyle: .alert
            )
            alertController = alert
            alert.addAction(UIAlertAction(title: "Discard", style: .`default`, handler: { (UIAlertAction) in
                shouldOverwrite = false
                semaphore.signal()
                alert.presentingViewController?.dismiss(animated: true, completion: nil)
            }))
            alert.addAction(UIAlertAction(title: "Overwrite", style: .`default`, handler: { (UIAlertAction) in
                shouldOverwrite = true
                semaphore.signal()
                alert.presentingViewController?.dismiss(animated: true, completion: nil)
            }))
            self.present(alert, animated: true, completion: nil)
        }
        let _ = semaphore.wait(timeout: .now() + 30.0)
        if shouldOverwrite == nil {
            mainQueue {
                alertController?.presentingViewController?.dismiss(animated: true, completion: nil)
            }
        }
        return shouldOverwrite
    }
}
#endif

// MARK: - CloudKit Extensions

/// UbiquityContainerIdentifier
///
/// iCloud Identifier
public enum UbiquityContainerIdentifier: String {
    
    case lock = "iCloud.com.colemancda.Lock"
}

public extension FileManager {
    
    /**
     Returns the URL for the iCloud container associated with the specified identifier and establishes access to that container.
     
     - Note: Do not call this method from your app’s main thread. Because this method might take a nontrivial amount of time to set up iCloud and return the requested URL, you should always call it from a secondary thread.
     */
    func ubiquityContainerURL(for identifier: UbiquityContainerIdentifier) -> URL? {
        assert(Thread.isMainThread == false, "Use iCloud from secondary thread")
        return url(forUbiquityContainerIdentifier: identifier.rawValue)
    }
}
