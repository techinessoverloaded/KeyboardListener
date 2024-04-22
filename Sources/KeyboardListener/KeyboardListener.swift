//
//  KeyboardPublisher.swift
//
//
//  Created by Arunprasadh C on 21/04/24.
//

import UIKit
import Combine

@objc public protocol RootViewProvider: AnyObject {
    @objc var rootView: UIView { get } // In order to enable overriding in extensions
}

extension UIView: RootViewProvider {
    public var rootView: UIView {
        return self
    }
}

extension UITableViewCell {
    public override var rootView: UIView {
        return contentView
    }
}

extension UICollectionViewCell {
    public override var rootView: UIView {
        return contentView
    }
}

extension UIViewController: RootViewProvider {
    public var rootView: UIView {
        return view
    }
}

@MainActor 
@propertyWrapper
public struct KeyboardListener {
    
    private var keyboardInfoCancellable: AnyCancellable?
    
    private var constraintPropertyCancellable: AnyCancellable?
    
    private var keyboardTopOffset: CGFloat = .zero
    
    private let shouldAnimateChanges: Bool
    
    public var wrappedValue: NSLayoutConstraint?
    
    public var projectedValue: AnyPublisher<Notification, Never> {
        return keyboardInfoPublisher
    }
    
    private var keyboardInfoPublisher: AnyPublisher<Notification, Never> {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
            .eraseToAnyPublisher()
    }
    
    private var firstView: UIView? {
        return wrappedValue?.firstItem as? UIView
    }
    
    private var secondView: UIView? {
        return wrappedValue?.secondItem as? UIView
    }

    public init(wrappedValue: NSLayoutConstraint? = nil, shouldAnimateChanges: Bool = true) {
        self.wrappedValue = wrappedValue
        self.shouldAnimateChanges = shouldAnimateChanges
    }
    
    public static subscript<OuterSelf: RootViewProvider>(
        _enclosingInstance observed: OuterSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<OuterSelf, NSLayoutConstraint?>,
        storage storageKeyPath: ReferenceWritableKeyPath<OuterSelf, Self>
    ) -> NSLayoutConstraint? {
        get {
            observed[keyPath: storageKeyPath].wrappedValue
        }
        set {
            observed[keyPath: storageKeyPath].wrappedValue = newValue
            if let newValue {
                observed[keyPath: storageKeyPath].keyboardInfoCancellable = observed[keyPath: storageKeyPath].keyboardInfoPublisher.sink { notification in
                    observed[keyPath: storageKeyPath].keyboardInfoReceived(notification, rootView: observed.rootView)
                }
                observed[keyPath: storageKeyPath].constraintPropertyCancellable = newValue.publisher(for: \.isActive, options: [.new]).sink { _ in
                    observed[keyPath: storageKeyPath].keyboardInfoPublisher
                }
            } else {
                observed[keyPath: storageKeyPath].keyboardInfoCancellable = nil
                observed[keyPath: storageKeyPath].constraintPropertyCancellable = nil
            }
        }
    }
    
    private mutating func keyboardInfoReceived(_ notification: Notification, rootView: UIView) {
        guard let constraint = wrappedValue,
              constraint.isActive,
              secondView == rootView,
              constraint.secondAttribute == .bottom || constraint.secondAttribute == .bottomMargin,
              constraint.firstAttribute == .bottom || constraint.firstAttribute == .bottomMargin
        else {
            return
        }
        guard let userInfo = notification.userInfo,
              let isKeyboardLocal = (userInfo[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber)?.boolValue,
              isKeyboardLocal,
              let screen = (notification.object as? UIScreen) ?? rootView.window?.windowScene?.screen
        else {
            return
        }
        
        var topOffset: CGFloat = .zero
        
        if notification.name == UIResponder.keyboardWillChangeFrameNotification,
           let keyboardEndFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            // Use that screen to get the coordinate space to convert from.
            let fromCoordinateSpace = screen.coordinateSpace

            // Get your view's coordinate space.
            let toCoordinateSpace: UICoordinateSpace = rootView
            
            // Convert the keyboard's frame from the screen's coordinate space to your view's coordinate space.
            let convertedKeyboardEndFrame = fromCoordinateSpace.convert(keyboardEndFrame, to: toCoordinateSpace)
            
            let viewIntersection = rootView.bounds.intersection(convertedKeyboardEndFrame)
                
            // Check whether the keyboard intersects your view before adjusting your offset.
            if !viewIntersection.isEmpty {
                    
                // Adjust the offset by the difference between the view's height and the height of the
                // intersection rectangle.
                topOffset = -(rootView.bounds.maxY - viewIntersection.minY)
            }
        }
        
        keyboardTopOffset = topOffset
        
        applyKeyboardTopOffset(to: rootView, constraint: constraint, userInfo: userInfo)
    }
    
    private func applyKeyboardTopOffset(to rootView: UIView, constraint: NSLayoutConstraint, userInfo: [AnyHashable: Any]) {
        constraint.constant = keyboardTopOffset
        
        if shouldAnimateChanges,
           let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
           let animationCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt {
            UIView.animate(withDuration: animationDuration, delay: 0, options: UIView.AnimationOptions(rawValue: animationCurve), animations: {
                rootView.layoutIfNeeded()
            })
        } else {
            rootView.layoutIfNeeded()
        }
    }
}
