//
//  ErrorAlert.swift
//  SmartLock
//
//  Created by Alsey Coleman Miller on 8/12/18.
//  Copyright © 2018 ColemanCDA. All rights reserved.
//

import Foundation
import UIKit

public extension UIViewController {
    
    /// Presents an error alert controller with the specified completion handlers.
    func showErrorAlert(_ localizedText: String,
                        okHandler: (() -> ())? = nil,
                        retryHandler: (()-> ())? = nil) {
        
        let alert = UIAlertController(title: R.string.localizable.alertError(),
            message: localizedText,
            preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: R.string.localizable.alertOk(), style: UIAlertAction.Style.`default`, handler: { (UIAlertAction) in
            
            okHandler?()
            
            alert.presentingViewController?.dismiss(animated: true, completion: nil)
        }))
        
        // optionally add retry button
        
        if let retryHandler = retryHandler {
            
            alert.addAction(UIAlertAction(title: R.string.localizable.alertRetry(), style: UIAlertAction.Style.`default`, handler: { (UIAlertAction) in
                
                retryHandler()
                
                alert.presentingViewController?.dismiss(animated: true, completion: nil)
            }))
        }
        
        self.present(alert, animated: true, completion: nil)
    }
}
