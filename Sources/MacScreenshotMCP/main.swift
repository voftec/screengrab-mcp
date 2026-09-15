import Foundation
import MCP

let server = Server(
    name: "screengrab-mcp",
    version: "0.2.0",
    capabilities: .init(
        resources: .init(listChanged: false),
        tools: .init(listChanged: false)
    )
)

await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: Tools.all)
}

await server.withMethodHandler(CallTool.self) { params in
    await Tools.call(params)
}

await server.withMethodHandler(ListResources.self) { _ in
    ListResources.Result(resources: CaptureStore.list())
}

await server.withMethodHandler(ReadResource.self) { params in
    ReadResource.Result(contents: [try CaptureStore.read(uri: params.uri)])
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
