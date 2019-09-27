import Foundation
import CoreData
import PusherPlatform

public class UserProvider: NSObject, DataProvider {
    
    // MARK: - Properties
    
    public private(set) var isFetchingMoreUsers: Bool
    public let logger: PPLogger?
    
    public weak var delegate: UserProviderDelegate?
    
    private var users: [User]
    
    private let userFactory: UserFactory
    
    // MARK: - Accessors
    
    public var numberOfUsers: Int {
        return self.users.count
    }
    
    // MARK: - Initializers
    
    init(logger: PPLogger? = nil) {
        self.isFetchingMoreUsers = false
        self.logger = logger
        self.users = []
        
        self.userFactory = UserFactory()
    }
    
    // MARK: - Public methods
    
    public func user(at index: Int) -> User? {
        return index >= 0 && index < self.users.count ? self.users[index] : nil
    }
    
    public func fetchMoreUsers(numberOfUsers: UInt, completionHandler: CompletionHandler? = nil) {
        guard !self.isFetchingMoreUsers else {
            if let completionHandler = completionHandler {
                // TODO: Return error
                completionHandler(nil)
            }
            
            return
        }
        
        self.isFetchingMoreUsers = true
        
        let lastUserIdentifier = self.users.last?.identifier ?? "-1"
        
        self.userFactory.receiveMoreUsers(numberOfUsers: Int(numberOfUsers), lastUserIdentifier: lastUserIdentifier, delay: 1.0) { users in
            let range = Range<Int>(uncheckedBounds: (lower: self.users.count, upper: self.users.count + users.count))
            
            self.users.append(contentsOf: users)
            
            self.isFetchingMoreUsers = false
            
            self.delegate?.userProvider(self, didAddUsersAtIndexRange: range)
            
            if let completionHandler = completionHandler {
                completionHandler(nil)
            }
        }
    }
    
}

// MARK: - Delegate

public protocol UserProviderDelegate: class {
    
    func userProvider(_ userProvider: UserProvider, didAddUsersAtIndexRange range: Range<Int>)
    
}