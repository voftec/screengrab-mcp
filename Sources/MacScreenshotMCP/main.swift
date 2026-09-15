import Foundation
import MCP

let server = Server(
    name: "mac-screenshot-mcp",
    version: "0.1.0",
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: Tools.all)
}

await server.withMethodHandler(CallTool.self) { params in
    await Tools.call(params)
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
