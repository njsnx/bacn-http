//
//  BaconHTTP.swift
//  BacnServer
//
//  Created by Neil Stewart on 20/01/2025.
//

import AWSLambdaEvents
import AWSLambdaRuntime
import Foundation
import HTTPTypes
import Logging
public protocol BaconAwsRequest {}

public struct BaconRequest {
    public var awsRequest: BaconAwsRequest
    public var pathParameters: [String: String]?
    public var decodedParameters: Codable?
    public var requestContent: String?
    public var decodedRequestContent: String?
    
    public func decodeParams<T: Codable>(_: T.Type = T.self) -> T? {
        do {
            return decodeData(T.self, data: pathParameters!)
        } catch {
            print("Decoding was not possibke")
            print(error)
            return nil
        }
    }
    
    public func decodeContent<T: Codable>(_: T.Type = T.self) -> T? {
        do {
            if let requestContent = requestContent {
                print(requestContent    )
                let data = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: Data(requestContent.utf8)))
                print(data)
                    
                let content = try JSONDecoder().decode(T.self, from: data)
                return content
//                return decodeData(T.self, data:  Data(requestContent.utf8))
            }
            return nil
        } catch {
            print("Decoding was not possibke")
            print(error)
            return nil
        }
    }
    
    private func decodeData<T: Codable>(_: T.Type = T.self, data inputData: Any) -> T? {
        do {
            
            let data = try JSONSerialization.data(withJSONObject: inputData, options: [])
            let content = try JSONDecoder().decode(T.self, from: data)
            return content
        } catch {
            print("Decoding was not possibke")
            print(error)
            return nil
        }
    }
}

public protocol BaconRoutes {
    func boot(request: BaconAwsRequest) -> BaconContent
}

public protocol BaconContent: Codable, Sendable {}

public class BaconRouteProvider {
    var logger: Logger = Logger(label: "bacn-http")
    var app: BaconApplication?
    var children = [String: BaconRouteProvider]()
    var parent: BaconRouteProvider?
    var routes = [String: BaconRoute]()
    var groups = [String: BaconRouteGroup]()

    public func grouped(by path: String) -> BaconRouteGroup {
        let group = BaconRouteGroup(path: path)
        children[path] = group
        return group
    }

    public func get(_ path: String = "/", use: @escaping (BaconRequest) -> BaconContent) {
        routes[HTTPRequest.Method.get.rawValue + path] = BaconRoute(
            path: path,
            method: .get,
            function: use
        )
    }
    
    public func get(_ path: String = "/", use: @escaping (BaconRequest) async -> BaconContent) {
        routes[HTTPRequest.Method.get.rawValue + path] = BaconRoute(
            path: path,
            method: .get,
            function: use
        )
    }
    

    public func patch(_ path: String = "/", use: @escaping (BaconRequest) -> BaconContent) {
        routes[HTTPRequest.Method.patch.rawValue + path] = BaconRoute(
            path: path,
            method: .post,
            function: use
        )
    }

    public func options(_ path: String = "/", use: @escaping (BaconRequest) -> BaconContent) {
        routes[HTTPRequest.Method.options.rawValue + path] = BaconRoute(
            path: path,
            method: .post,
            function: use
        )
    }

    public func delete(_ path: String = "/", use: @escaping (BaconRequest) -> BaconContent) {
        routes[HTTPRequest.Method.delete.rawValue + path] = BaconRoute(path: path, method: .post, function: use)
    }

    public func put(_ path: String = "/", use: @escaping (BaconRequest) -> BaconContent) {
        routes[HTTPRequest.Method.put.rawValue + path] = BaconRoute(path: path, method: .post, function: use)
    }

    public func post(_ path: String = "/", use: @escaping (BaconRequest) async -> BaconContent) {
        routes[HTTPRequest.Method.post.rawValue + path] = BaconRoute(path: path, method: .post, function: use)
    }

    public func processParentPath(_ path: String = "", dest: BaconRouteProvider) -> [String: BaconRoute] {
        var processedRoutes = [String: BaconRoute]()

        for (_, route) in dest.routes {
            processedRoutes["\(route.method)\(path)\(route.path)"] = route
        }
        return processedRoutes
    }

    public func loopChildren(_ children: [String: BaconRouteProvider], path parentPath: String = "") -> [String: BaconRoute] {
        var processedRoutes = [String: BaconRoute]()
        for (path, dest) in children {
            processedRoutes.merge(processParentPath(parentPath + path, dest: dest)) { _, new in new }

            processedRoutes.merge(loopChildren(dest.children, path: path)) { _, new in new }
        }
        return processedRoutes
    }

    public func findRoute(_ path: String, method: HTTPRequest.Method) -> (BaconRoute?, [String: String]?) {
        var combinedRoutes: [String: BaconRoute] = processParentPath(dest: self)

        combinedRoutes.merge(loopChildren(children)) { _, current in current }
        
        for route in combinedRoutes.keys {
            logger.info(Logger.Message(stringLiteral: route))
            if let pathParameters = matchRoute(
                route,
                with: method.rawValue + "/" + path + "/"
            ) {
                return (combinedRoutes[route], pathParameters)
            }
        }

        return (nil, nil)
    }

    public func matchRoute(_ routePath: String, with requestPath: String) -> [String: String]? {
        let routeComponents = routePath.split(separator: "/")
        let requestComponents = requestPath.split(separator: "/")

        guard routeComponents.count == requestComponents.count else {
            return nil
        }

        var params: [String: String] = [:]

        for (routePart, requestPart) in zip(routeComponents, requestComponents) {
            if routePart.hasPrefix(":") {
                let parameterName = String(routePart.dropFirst())
                params[parameterName] = String(requestPart)
            } else if routePart != requestPart {
                return nil
            }
        }
        return params
    }
}

public class BaconApplication: BaconRouteProvider {
    public var context: LambdaContext
    public var routeCollections: [BaconRoutesCollection] = []
    public init(context: LambdaContext) {
        self.context = context
    }

    public func register(_ collection: BaconRoutesCollection) {
        collection.boot(routes: self)
        routeCollections.append(collection)
    }

    public override func grouped(by path: String) -> BaconRouteGroup {
        let group = super.grouped(by: path)
        group.app = self
        return group
    }

    public func routeRequest(event: APIGatewayV2Request) async throws -> APIGatewayV2Response {
        // get all children

        let path = event.rawPath
        let method = event.context.http.method
        print("Looking for route for \(method.rawValue) \(path)")

        let (functionToRun, pathParams) = findRoute(
            path,
            method: method
        )
        if let functionToRun = functionToRun {
            print(
                "Found function to run for path \(path) and method \(method.rawValue)"
            )

            let raconRequest = BaconRequest(
                awsRequest: event,
                pathParameters: pathParams,
                requestContent: event.body
            )

            let result = await functionToRun.function(raconRequest) as BaconContent
            var header = HTTPHeaders()
            context.logger.info("HTTP Event recieved")
            header["content-type"] = "application/json"
            return try APIGatewayV2Response(
                statusCode: .ok,
                headers: header,
                encodableBody: result
            )
        } else {
            return try APIGatewayV2Response(
                statusCode: .notFound,
                encodableBody: Abort(.notFound)
            )
        }
    }
}

extension String: BaconContent {}
extension APIGatewayV2Request: BaconAwsRequest {}
public struct BaconRoute {
    var path: String
    var method: HTTPRequest.Method
    var function: (BaconRequest) async -> BaconContent
}

public class BaconRouteGroup: BaconRouteProvider {
    var path: String
    init(path: String, parent _: BaconRouteProvider? = nil) {
        self.path = path
    }
}

public struct Abort: BaconContent, Codable, Sendable {
    public  var reason: String
    public init(_ reason: HTTPResponse.Status = .ok) {
        self.reason = reason.reasonPhrase
    }
}

public protocol BaconRoutesCollection {
    func boot(routes: BaconRouteProvider)
}
