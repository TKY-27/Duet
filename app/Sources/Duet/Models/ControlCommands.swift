import Foundation

struct SetRolesCommand: Encodable {
    let type = "setRoles"
    var roles: Roles
}

struct InjectHumanCommand: Encodable {
    let type = "injectHuman"
    var to: Recipient
    var message: String
}

struct SimpleCommand: Encodable {
    var type: String
}
