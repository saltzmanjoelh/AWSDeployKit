//
//  ShellExecutor.swift
//  
//
//  Created by Joel Saltzman on 3/25/21.
//

import Foundation
import ShellOut
import LogKit
import Logging

public struct ShellExecutor {
    /// The function to perform the shellOut action. You only need to modify this for tests.
    public static var shellOutAction: (String, [String], String, Process, FileHandle?, FileHandle?) throws -> String = shellOut(to:arguments:at:process:outputHandle:errorHandle:)
    /// Executes a shell script
    @discardableResult
    public static func run(
        _ command: String,
        arguments: [String] = [],
        at path: String = ".",
        process: Process = .init(),
        outputHandle: FileHandle? = nil,
        errorHandle: FileHandle? = nil
    ) throws -> String {
//        Logger.default.logLevel = .trace
        let cmd = ([command] + arguments).joined(separator: " ")
        Logger.default.trace("Running shell command: \(cmd)")
        return try shellOutAction(command, arguments, path, process, outputHandle, errorHandle)
    }
}
