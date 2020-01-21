


enum Action {
    case subscriptionEvent(Wire.Event.EventType)
    case received(user: Wire.User)
    case fetching(userWithIdentifier: String)
}
extension Action: Equatable {}


protocol StoreDelegate: class {
    func store(_ store: Store, didUpdateState state: State)
}


protocol HasStore {
    var store: Store { get }
}

protocol Store {
    func action(_ action: Action)
}

class ConcreteStore: Store {
    
    typealias Dependencies = Any // No dependencies for now
    
    let dependencies: Dependencies
    weak var delegate: StoreDelegate?
    
    var state: State {
        didSet {
            self.delegate?.store(self, didUpdateState: self.state)
        }
        
    }
    
    init(dependencies: Dependencies, delegate: StoreDelegate?) {
        self.dependencies = dependencies
        self.delegate = delegate
        self.state = State.emptyState
    }
    
    func action(_ action: Action) {
        
        let existingState = self.state
        
        let newState: State
        
        switch action {
            
        case let .subscriptionEvent(eventType):
            
            switch eventType {
                
            case let .initialState(initialState):
                // TODO move elsewhere
                let currentUser = Internal.User(
                    identifier: initialState.currentUser.identifier,
                    name: initialState.currentUser.name
                )
                
                var joinedRooms = [Internal.Room]()
                for wireRoom in initialState.rooms {
                    let joinedRoom = Internal.Room(identifier: wireRoom.identifier, name: wireRoom.name)
                    joinedRooms.append(joinedRoom)
                }
                
                newState = State(
                    currentUser: currentUser,
                    joinedRooms: joinedRooms
                )

            default:
                fatalError()
            }
            
        case let .received(user: wireUser):
            // TODO
            let internalUser = Internal.User(
                identifier: wireUser.identifier,
                name: wireUser.name
            )
            
            print("unimplemented, received user \(internalUser)")
            fatalError()
            
            newState = existingState
            
        case let .fetching(userWithIdentifier):
            // TODO
            print("unimplemented, fetching user \(userWithIdentifier)")
            fatalError()
            
            newState = existingState
        }
        
        self.state = newState
    }
}