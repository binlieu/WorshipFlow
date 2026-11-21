// CUE-002b (item 5): the remote server's door into the app. Every request is handed to the one command path and answered when
// its command has finished, so a phone can never run a command in the middle of the operator's.
import Foundation
import CueEngine
import RemoteControl

/// `unowned` is safe: the model owns the server, which owns this, and the model stops the server before it goes.
final class CueRemoteTarget: RemoteControlTarget {
    unowned let model: CueModel
    init(model: CueModel) { self.model = model }

    func perform(_ command: CueTransport) async throws {
        if let problem = await model.run(.transport(command), from: .remote) { throw RemoteTargetError.rejected(problem) }
    }

    func runMacro(id: UUID) async throws {
        guard await model.hasMacro(id) else { throw RemoteTargetError.unknownMacro }
        await model.run(.runMacro(id), from: .remote)
    }

    func snapshot() async -> RemoteState { await model.remoteSnapshot() }
}
