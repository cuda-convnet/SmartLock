//
//  AppDelegate.swift
//  SmartLock
//
//  Created by Alsey Coleman Miller on 8/12/18.
//  Copyright © 2018 ColemanCDA. All rights reserved.
//

import Foundation
import UIKit
import CoreBluetooth
import CoreLocation
import UserNotifications
import CoreSpotlight
import CloudKit
import Bluetooth
import GATT
import CoreLock
import LockKit
import JGProgressHUD
import OpenCombine

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    
    static var shared: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }
    
    // MARK: - Properties

    var window: UIWindow?
    
    private(set) var didBecomeActive: Bool = false
    
    let appLaunch = Date()
    
    lazy var bundle = Bundle.Lock(rawValue: Bundle.main.bundleIdentifier ?? "") ?? .app
    
    #if DEBUG || targetEnvironment(macCatalyst)
    private var updateTimer: Timer?
    #endif
    
    private var locksObserver: OpenCombine.AnyCancellable?
        
    // MARK: - UIApplicationDelegate
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Create logging file
        Log.shared = .mainApp
        
        // print app info
        log("\(bundle.symbol) Launching SmartLock v\(Bundle.InfoPlist.shortVersion) Build \(Bundle.InfoPlist.version)")
        
        #if DEBUG
        defer { log("\(bundle.symbol) App finished launching in \(String(format: "%.3f", Date().timeIntervalSince(appLaunch)))s") }
        #endif
        
        // set global appearance
        UIView.configureLockAppearance()
        
        #if DEBUG
        do {
            try R.validate()
            try RLockKit.validate()
        } catch {
            print(error)
            assertionFailure("Could not validate R.swift \(error)")
        }
        #endif
        
        // load store singleton
        let _ = Store.shared
        
        // setup logging
        LockManager.shared.log = { log("🔒 LockManager: " + $0) }
        LockNetServiceClient.shared.log = { log("🌐 NetService: " + $0) }
        BeaconController.shared.log = { log("📶 \(BeaconController.self): " + $0) }
        SpotlightController.shared.log = { log("🔦 \(SpotlightController.self): " + $0) }
        WatchController.shared.log = { log("⌚️ \(WatchController.self): " + $0) }
        if #available(iOS 10.0, *) {
            UserNotificationCenter.shared.log = { log("📨 \(UserNotificationCenter.self): " + $0) }
        }
        
        // request permissions
        //BeaconController.shared.allowsBackgroundLocationUpdates = true
        BeaconController.shared.requestAlwaysAuthorization()
        if #available(iOS 10.0, *) {
            UserNotificationCenter.shared.requestAuthorization()
        }
        application.registerForRemoteNotifications()
        
        // handle notifications
        if #available(iOS 10.0, *) {
            UserNotificationCenter.shared.handleActivity = { [unowned self] (activity) in
                mainQueue { self.handle(activity: activity) }
            }
            UserNotificationCenter.shared.handleURL = { [unowned self] (url) in
                mainQueue { self.handle(url: url) }
            }
        }
        
        // setup watch
        if WatchController.isSupported {
            WatchController.shared.activate()
            WatchController.shared.keys = { Store.shared[key: $0] }
            WatchController.shared.context = .init(
                applicationData: Store.shared.applicationData
            )
            locksObserver = Store.shared.locks.sink { _ in
                WatchController.shared.context = .init(
                    applicationData: Store.shared.applicationData
                )
            }
        }
        
        #if targetEnvironment(macCatalyst)
        // scan periodically in macOS
        setupBackgroundUpdates()
        #else
        // background fetch in iOS
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        #endif
                
        // queue post-app initialization loading
        DispatchQueue.main.async { [unowned self] in
            
            // load reachability
            if #available(iOS 12.0, *) {
                let _ = NetworkMonitor.shared
            }
            
            // subscribe to push notifications
            self.queueDidLaunchOperations()
        }
        
        // handle url
        if let url = launchOptions?[.url] as? URL {
            open(url: url)
        }
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        
        log("\(bundle.symbol) Will resign active")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        
        let bundle = self.bundle
        log("\(bundle.symbol) Did enter background")
        logBackgroundTimeRemaining()
        
        // update beacons
        BeaconController.shared.scanBeacons()
        
        // only scan and sync in background when low power mode is disabled.
        guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
        
        // scan in background
        if Store.shared.lockManager.central.state == .poweredOn {
            let bluetoothTask = application.beginBackgroundTask(withName: "BluetoothScan", expirationHandler: {
                log("\(bundle.symbol) Background task expired")
            })
            DispatchQueue.bluetooth.async { [unowned self] in
                // scan for nearby devices
                do { try Store.shared.scan(duration: 3.0) }
                catch { log("⚠️ Unable to scan: \(error.localizedDescription)") }
                // read information characteristic
                for device in Store.shared.peripherals.value.values {
                    guard Store.shared.lockInformation.value[device.scanData.peripheral] == nil
                        else { continue }
                    do { try Store.shared.readInformation(device) }
                    catch { log("⚠️ Unable to read information: \(error.localizedDescription)") }
                }
                DispatchQueue.main.async { [weak self] in
                    self?.logBackgroundTimeRemaining()
                    log("\(bundle.symbol) Bluetooth background task ended")
                    application.endBackgroundTask(bluetoothTask)
                }
            }
        }
        
        // attempt to sync with iCloud in background
        let cloudTask = application.beginBackgroundTask(withName: "iCloudSync", expirationHandler: {
            log("\(bundle.symbol) Background task expired")
        })
        DispatchQueue.cloud.async {
            do { try Store.shared.syncCloud() }
            catch { log("⚠️ Unable to sync: \(error.localizedDescription)") }
            DispatchQueue.main.async { [weak self] in
                self?.logBackgroundTimeRemaining()
                log("\(bundle.symbol) iCloud background task ended")
                application.endBackgroundTask(cloudTask)
            }
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        
        log("\(bundle.symbol) Will enter foreground")
                
        // update cache if modified by extension
        Store.shared.loadCache()
        
        // save energy
        guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
        
        // attempt to scan for all known locks if they are not in central cache
        if Store.shared.lockManager.central.state == .poweredOn {
            DispatchQueue.bluetooth.async {
                let locks = Store.shared.locks.value.keys
                guard locks.contains(where: { Store.shared.device(for: $0) == nil }) else { return }
                // scan for nearby devices
                do { try Store.shared.scan(duration: 3.0) }
                catch { log("⚠️ Unable to scan: \(error.localizedDescription)") }
                // read information characteristic
                for device in Store.shared.peripherals.value.values {
                    guard Store.shared.lockInformation.value[device.scanData.peripheral] == nil
                        else { continue }
                    do { try Store.shared.readInformation(device) }
                    catch { log("⚠️ Unable to read information: \(error.localizedDescription)") }
                }
            }
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        
        log("\(bundle.symbol) Did become active")
        
        didBecomeActive = true
        application.applicationIconBadgeNumber = 0
                        
        // scan for iBeacons
        BeaconController.shared.scanBeacons()
        
        // save energy
        guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
        
        // attempt to sync with iCloud
        tabBarController.syncCloud()
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        
        log("\(bundle.symbol) Will terminate")
        
        // scan for iBeacons
        BeaconController.shared.scanBeacons()
    }
    
    func application(_ application: UIApplication, handleOpen url: URL) -> Bool {
        #if DEBUG
        print(#function, "\n", url)
        #endif
        return open(url: url)
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        #if DEBUG
        print(#function, "\n", url)
        if options.isEmpty == false {
            print((options as NSDictionary).description)
        }
        #endif
        return open(url: url)
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        let bundle = self.bundle
        log("\(bundle.symbol) Perform background fetch")
        logBackgroundTimeRemaining()
        
        BeaconController.shared.scanBeacons()
        
        // 30 sec max background fetch
        var result: UIBackgroundFetchResult = .noData
        let applicationData = Store.shared.applicationData
        let information = Array(Store.shared.lockInformation.value.values)
        DispatchQueue.bluetooth.async { [unowned self] in
            do {
                // scan for locks
                try Store.shared.scan(duration: 5.0)
                // make sure each stored lock is visible
                let locks = Store.shared.locks.value
                    .lazy
                    .sorted(by: { $0.value.key.created < $1.value.key.created })
                    .lazy
                    .map { $0.key }
                    .lazy
                    .filter { Store.shared.device(for: $0) == nil }
                    .prefix(10)
                // scan for locks not found
                for lock in locks {
                    let _ = try Store.shared.device(for: lock, scanDuration: 1.0)
                }
            } catch {
                log("⚠️ Unable to scan: \(error.localizedDescription)")
                result = .failed
            }
            // attempt to sync with iCloud
            DispatchQueue.cloud.async {
                do { try Store.shared.syncCloud() }
                catch {
                    log("⚠️ Unable to sync: \(error.localizedDescription)")
                    result = .failed
                }
                if result != .failed {
                    if applicationData == Store.shared.applicationData,
                        information == Array(Store.shared.lockInformation.value.values) {
                        result = .noData
                    } else {
                        result = .newData
                    }
                }
                mainQueue { self.logBackgroundTimeRemaining() }
                log("\(bundle.symbol) Background fetch ended")
                completionHandler(result)
            }
        }
    }
    
    func application(_ application: UIApplication, willContinueUserActivityWithType userActivityType: String) -> Bool {
        
        return true
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        
        log("Continue activity \(userActivity.activityType)")
        if #available(iOS 12.0, *),
            let persistentIdentifier = userActivity.persistentIdentifier {
            log("\(persistentIdentifier)")
        }
        log("\((userActivity.userInfo as NSDictionary?)?.description ?? "")")
        var userInfo = [AppActivity.UserInfo: Any](minimumCapacity: userActivity.userInfo?.count ?? 0)
        for (key, value) in userActivity.userInfo ?? [:] {
            guard let key = key as? String,
                let userInfoKey = AppActivity.UserInfo(rawValue: key)
                else { continue }
            userInfo[userInfoKey] = value
        }
        
        switch userActivity.activityType {
        case CSSearchableItemActionType:
            guard let activityIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                let activity = AppActivity.ViewData(rawValue: activityIdentifier)
                else { return false }
            self.handle(activity: .view(activity))
            return false
        case NSUserActivityTypeBrowsingWeb:
            return false
        case AppActivityType.screen.rawValue:
            guard let screenString = userInfo[.screen] as? String,
                let screen = AppActivity.Screen(rawValue: screenString)
                else { return false }
            self.handle(activity: .screen(screen))
        case AppActivityType.view.rawValue:
            if let lockString = userInfo[.lock] as? String,
                let lock = UUID(uuidString: lockString) {
                self.handle(activity: .view(.lock(lock)))
            } else {
                return false
            }
        case AppActivityType.action.rawValue:
            guard let actionString = userInfo[.action] as? String,
                let action = AppActivity.ActionType(rawValue: actionString)
                else { return false }
            switch action {
            case .unlock:
                guard let lockString = userInfo[.lock] as? String,
                    let lock = UUID(uuidString: lockString)
                    else { return false }
                self.handle(activity: .action(.unlock(lock)))
            case .shareKey:
                guard let lockString = userInfo[.lock] as? String,
                    let lock = UUID(uuidString: lockString)
                    else { return false }
                self.handle(activity: .action(.shareKey(lock)))
            }
        default:
            return false
        }
        
        return true
    }
    
    func applicationSignificantTimeChange(_ application: UIApplication) {
        
        log("\(bundle.symbol) Significant time change")
        
        // refresh beacons
        BeaconController.shared.scanBeacons()
    }
    
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        
        
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        log("📲 Recieved push notification")
        #if DEBUG
        print((userInfo as NSDictionary).description)
        #endif
        
        DispatchQueue.app.async {
            
            do {
                if let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
                    
                    switch cloudKitNotification {
                    case let querySubcription as CKQueryNotification:
                        if let recordID = querySubcription.recordID, recordID.recordName.contains(CloudShare.NewKey.ID.cloudRecordType) {
                            try Store.shared.fetchCloudNewKeys { (_, invitation) in
                                mainQueue {
                                    if application.applicationState == .background {
                                        UserNotificationCenter.shared.postNewKeyShareNotification(invitation)
                                        application.applicationIconBadgeNumber += 1
                                    }
                                }
                            }
                        }
                    default:
                        break
                    }
                }
            } catch {
                log("⚠️ Push notification error: \(error.localizedDescription)")
            }
            
            mainQueue { completionHandler(.newData) }
        }
    }
}

extension AppDelegate {
    
    var tabBarController: TabBarController {
        guard let tabBarController = window?.rootViewController as? TabBarController
            else { fatalError() }
        return tabBarController
    }
}

private extension AppDelegate {
    
    func queueDidLaunchOperations() {
        
        // CloudKit discoverability
        DispatchQueue.cloud.asyncAfter(deadline: .now() + 3.0) {
            do {
                guard try Store.shared.cloud.accountStatus() == .available else { return }
                let status = try Store.shared.cloud.requestPermissions()
                log("☁️ CloudKit permisions \(status == .granted ? "granted" : "not granted")")
            }
            catch { log("⚠️ Could not request CloudKit permissions. \(error.localizedDescription)") }
        }
        
        // CloudKit push notifications
        DispatchQueue.app.async {
            do {
                guard try Store.shared.cloud.accountStatus() == .available else { return }
                try Store.shared.cloud.subcribeNewKeyShares()
            }
            catch { log("⚠️ Could subscribe to new shares. \(error)") }
        }
    }
}

private extension AppDelegate {
    
    private static let intervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
    
    func logBackgroundTimeRemaining() {
        
        let backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
        let start = Date()
        let timeString = type(of: self).intervalFormatter.string(from: start, to: start + backgroundTimeRemaining)
        log("\(bundle.symbol) Background time remaining: \(timeString)")
    }
}

#if DEBUG || targetEnvironment(macCatalyst)
private extension AppDelegate {
    
    @available(macOS 10.13, iOS 10.0, *)
    func setupBackgroundUpdates() {
        
        let interval = 90.0
        updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateBackground()
        }
    }
    
    func updateBackground() {
        
        let bundle = self.bundle
        log("\(bundle.symbol) Will update data")
        
        DispatchQueue.bluetooth.async {
            do {
                // scan for locks
                try Store.shared.scan(duration: 3.0)
                // make sure each stored lock is visible
                for lock in Store.shared.locks.value.keys {
                    let _ = try Store.shared.device(for: lock, scanDuration: 1.0)
                }
            } catch { log("⚠️ Unable to scan: \(error.localizedDescription)") }
            // attempt to sync with iCloud
            DispatchQueue.cloud.async {
                do { try Store.shared.syncCloud() }
                catch { log("⚠️ Unable to sync: \(error.localizedDescription)") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    log("\(bundle.symbol) Updated data")
                }
            }
        }
    }
}
#endif

// MARK: - URL Handling

internal extension AppDelegate {
    
    @discardableResult
    func open(url: URL) -> Bool {
        
        if url.isFileURL {
            open(file: url)
            return true
        } else if let lockURL = LockURL(rawValue: url) {
            open(url: lockURL)
            return true
        } else {
            return false
        }
    }
    
    func open(file url: URL) {
        
        let document = NewKeyDocument(fileURL: url)
        document.open { [weak self] _ in
            assert(Thread.isMainThread)
            if let invitation = document.invitation {
                self?.tabBarController.open(newKey: invitation)
            }
        }
    }
    
    func open(url: LockURL) {
        tabBarController.handle(url: url)
    }
}

// MARK: - LockActivityHandling

extension AppDelegate: LockActivityHandling {
    
    func handle(url: LockURL) {
        tabBarController.handle(url: url)
    }
    
    func handle(activity: AppActivity) {
        tabBarController.handle(activity: activity)
    }
}
