import Foundation
import CoreData
import PusherPlatform

public class Chatkit {
    
    // MARK: - Properties
    
    public private(set) var currentUser: User?
    public private(set) var connectionStatus: ConnectionStatus
    public let logger: PPLogger
    
    public weak var delegate: ChatkitDelegate?
    
    let persistenceController: PersistenceController
    let networkingController: NetworkingController
    
    var hiddenCurrentUser: User!
    
    // MARK: - Accessors
    
    public var instanceLocator: String {
        return self.networkingController.instanceLocator
    }
    
    public var tokenProvider: PPTokenProvider {
        return self.networkingController.tokenProvider
    }
    
    // MARK: - Initializers
    
    public init(instanceLocator: String, tokenProvider: PPTokenProvider, logger: PPLogger = PPDefaultLogger()) throws {
        self.logger = logger
        
        guard let model = NSManagedObjectModel.mergedModel(from: [Bundle.current]) else {
            logger.log("Failed to load Chatkit data model.", logLevel: .error)
            throw PersistenceError.objectModelNotFound
        }
        
        let storeDescription = NSPersistentStoreDescription(inMemoryPersistentStoreDescription: ())
        self.persistenceController = try PersistenceController(model: model, storeDescriptions: [storeDescription], logger: logger) { error in
            if let error = error {
                logger.log("Failed to load persistent stores with error: \(error.localizedDescription).", logLevel: .error)
            }
        }
        
        self.connectionStatus = .disconnected
        
        let eventParser = ModularEventParser(logger: self.logger)
        eventParser.register(parser: ChatEventParser(persistenceController: self.persistenceController, logger: self.logger), for: .chat, with: .version6)
        
        self.networkingController = try NetworkingController(instanceLocator: instanceLocator, tokenProvider: tokenProvider, eventParser: eventParser, logger: self.logger)
        
        var hiddenCurrentUser: User? = nil
        
        self.persistenceController.mainContext.performAndWait {
            let userEntity = UserEntityFactory.createCurrentUser(in: self.persistenceController.mainContext)
            
            self.persistenceController.save()
            
            hiddenCurrentUser = try! userEntity.snapshot()
        }
        
        self.hiddenCurrentUser = hiddenCurrentUser!
    }
    
    // MARK: - Public methods
    
    public func connect(completionHandler: CompletionHandler? = nil) {
        guard self.connectionStatus == .disconnected else {
            return
        }
        
        self.connectionStatus = .connecting
        self.delegate?.chatkit(self, didChangeConnectionStatus: self.connectionStatus)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.connectionStatus = .connected
            self.currentUser = self.hiddenCurrentUser
            
            self.delegate?.chatkit(self, didChangeConnectionStatus: self.connectionStatus)
            
            if let currentUser = self.currentUser {
                self.delegate?.chatkit(self, didUpdateCurrentUser: currentUser)
            }
            
            if let completionHandler = completionHandler {
                completionHandler(nil)
            }
        }
    }
    
    public func disconnect() {
        guard self.connectionStatus == .connected else {
            return
        }
        
        self.connectionStatus = .disconnected
        self.delegate?.chatkit(self, didChangeConnectionStatus: self.connectionStatus)
    }
    
    public func createUsersProvider() -> UsersProvider {
        return UsersProvider()
    }
    
    public func createAvailableRoomsProvider() -> AvailableRoomsProvider {
        return AvailableRoomsProvider()
    }
    
    public func createJoinedRoomsProvider() -> JoinedRoomsProvider {
        return JoinedRoomsProvider(currentUser: self.hiddenCurrentUser, persistenceController: self.persistenceController)
    }
    
    public func createRoomDetailsProvider(for room: Room) -> RoomDetailsProvider {
        return RoomDetailsProvider(room: room, currentUser: self.hiddenCurrentUser, persistenceController: self.persistenceController)
    }
    
}

// MARK: - Delegate

public protocol ChatkitDelegate: class {
    
    func chatkit(_ chatkit: Chatkit, didUpdateCurrentUser currentUser: User)
    func chatkit(_ chatkit: Chatkit, didChangeConnectionStatus connectionStatus: ConnectionStatus)
    
}