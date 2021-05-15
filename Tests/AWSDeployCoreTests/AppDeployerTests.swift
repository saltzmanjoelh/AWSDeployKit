//
//  AWSDeployTests.swift
//
//
//  Created by Joel Saltzman on 3/18/21.
//

@testable import AWSDeployCore
import Foundation
import Logging
import LogKit
import SotoS3
@testable import SotoTestUtils
import XCTest

class AppDeployerTests: XCTestCase {
    
    var testServices = TestServices()
    
    override func setUp() {
        continueAfterFailure = false
        testServices = TestServices()
    }
    override func tearDown() {
        ShellExecutor.resetAction()
    }

    func testVerifyConfiguration_directoryPathUpdateWithDot() throws {
        // Given a "." path
        var instance = try AppDeployer.parseAsRoot(["-d", ".", "my-function"]) as! AppDeployer

        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: testServices)

        // Then the directoryPath should be updated
        XCTAssertNotEqual(instance.directoryPath, "./")
        XCTAssertNotEqual(instance.directoryPath, ".")
    }

    func testVerifyConfiguration_directoryPathUpdateWithDotSlash() throws {
        // Given a "." path
        var instance = try AppDeployer.parseAsRoot(["-d", "./", "my-function"]) as! AppDeployer

        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: testServices)

        // Then the directoryPath should be updated
        XCTAssertNotEqual(instance.directoryPath, "./")
        XCTAssertNotEqual(instance.directoryPath, ".")
    }

    func testVerifyConfiguration_logsWhenSkippingProducts() throws {
        // Given a product to skip
        let path = try createTempPackage()
        var instance = try AppDeployer.parseAsRoot(["-s", ExamplePackage.executableThree, "-p", path]) as! AppDeployer

        // When calling verifyConfiguration
        try instance.verifyConfiguration(services: testServices)

        // Then a "Skipping $PRODUCT" log should be received
        let messages = testServices.logCollector.logs.allMessages()
        XCTAssertString(messages, contains: "Skipping: \(ExamplePackage.executableThree)")
    }
    func testVerifyConfiguration_throwsWithMissingProducts() throws {
        // Given a package without any executables
        var instance = AppDeployer()
        instance.directoryPath = "./"
        instance.products = []
        instance.skipProducts = ""
        instance.publishBlueGreen = false
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            let packageManifest = "{\"products\" : []}"
            return .stubMessage(level: .trace, message: packageManifest)
        }
        
        do {
            // When calling verifyConfiguration
            try instance.verifyConfiguration(services: testServices)
            
            XCTFail("An error should have been thrown and products should have been empty instead of: \(instance.products)")
        } catch AppDeployerError.missingProducts {
            // Then the AppDeployerError.missingProducts error should be thrown
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func testGetProducts() throws {
        // Given a package with a library and multiple executables
        let path = try createTempPackage()
        let instance = AppDeployer()

        // When calling getProducts
        let result = try instance.getProducts(from: path, logger: testServices.logger)

        // Then all executables should be returned
        XCTAssertEqual(result.count, ExamplePackage.executables.count)
    }
    func testGetProducts_throwsWithMissingProducts() throws {
        // Given a package without any executables
        var instance = AppDeployer()
        instance.directoryPath = "./"
        instance.products = []
        instance.skipProducts = ""
        instance.publishBlueGreen = false
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            let packageManifest = """
                {
                  "products" : [
                    {
                      "name" : "Core",
                      "type" : {
                        "library" : [
                          "automatic"
                        ]
                      }
                    }
                  ]
                }
                """
            return .stubMessage(level: .trace, message: packageManifest)
        }
        defer { ShellExecutor.resetAction() }
        
        do {
            // When calling getProdcuts
            let result = try instance.getProducts(from: "")
            
            XCTFail("An error should have been thrown and products should have been empty instead of: \(result)")
        } catch AppDeployerError.missingProducts {
            // Then an error should be thrown
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func testRunDoesNotThrow() throws {
        // Setup
        Services.shared = testServices
        defer {
            Services.shared = Services()
        }
        let functionName = "my-function"
        let archivePath = "/tmp/\(functionName)_yyyymmdd_HHMM.zip"
        FileManager.default.createFile(atPath: archivePath, contents: "File".data(using: .utf8)!, attributes: nil)
        ShellExecutor.shellOutAction = { (_, _, _) throws -> LogCollector.Logs in
            return .stubMessage(level: .trace, message: archivePath)
        }
        defer { ShellExecutor.resetAction() }
        let functionConfiguration = String(
            data: try JSONEncoder().encode([
                "FunctionName": functionName,
                "RevisionId": "1234",
                "Version": "4",
                "CodeSha256": UUID().uuidString,
            ]),
            encoding: .utf8
        )!
        // getFunctionConfiguration, updateFunctionCode, publishLatest, verifyLambda, updateAlias
        var fixtureResults: [ByteBuffer] = .init(repeating: ByteBuffer(string: functionConfiguration), count: 5)
        let resultReceived = expectation(description: "Result received")

        // run() uses wait() so do it in the background
        DispatchQueue.global().async {
            do {
                // Given a valid configuation
                var instance = try AppDeployer.parseAsRoot(["-p", "my-function"]) as! AppDeployer

                // When calling run
                try instance.run()

            } catch {
                // Then no errors should be thrown
                XCTFail(String(describing: error))
            }
            resultReceived.fulfill()
        }

        // Wait for the server to process
        try testServices.awsServer.processRaw { request in
            guard let result = fixtureResults.popLast() else {
                let error = AWSTestServer.ErrorType(status: 500, errorCode: "InternalFailure", message: "Unhandled request: \(request)")
                return .error(error, continueProcessing: false)
            }
            return .result(.init(httpStatus: .ok, body: result), continueProcessing: fixtureResults.count > 0)
        }
        XCTAssertEqual(fixtureResults.count, 0, "Not all calls were performed.")
        wait(for: [resultReceived], timeout: 2.0)
    }

    func testRunWithRealPackage() throws {
        // This is more of an integration test. We won't stub the services
        let path = try createTempPackage()
        // Configure the CollectingLogger
        let collector = LogCollector()
        Services.shared.logger = CollectingLogger(label: #function, logCollector: collector)
        Services.shared.logger.logLevel = .trace

        // Given a valid configuation (not calling publish for the tests)
        var instance = try AppDeployer.parseAsRoot(["-d", path, ExamplePackage.executableOne]) as! AppDeployer

        // When calling run
        // Then no errors should be thrown
        XCTAssertNoThrow(try instance.run())
        // and the zip should exist. The last line of the last log should contain the zip path
        let zipPath = collector.logs.allEntries.last?.message.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").last
        XCTAssertNotNil(zipPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipPath!), "File does not exist: \(zipPath!)")
    }
    
    func testRemoveSkippedProducts() {
        // Given a list of skipProducts for a process
        let skipProducts = ExamplePackage.executableThree
        let processName = ExamplePackage.executableTwo // Simulating that executableTwo is the executable that does the deployment
        
        // When calling removeSkippedProducts
        let result = AppDeployer.removeSkippedProducts(skipProducts,
                                                       from: ExamplePackage.executables,
                                                       logger: testServices.logger,
                                                       processName: processName)
        
        // Then the remaining products should not contain the skipProducts
        XCTAssertFalse(result.contains(skipProducts), "The \"skipProducts\": \(skipProducts) should have been removed.")
        // or a product with a matching processName
        XCTAssertFalse(result.contains(processName), "The \"processName\": \(processName) should have been removed.")
    }
}
