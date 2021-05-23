import Foundation

/**
 Duplicates the data from `input` into each of the `outputs`.
 Following the precedent of `standardInput`/`standardOutput`/`standardError` in `Process` from `Foundation`,
    we accept the type `Any`, but throw a precondition failure if the arguments are not `Pipe` or `FileHandle`.
 https://github.com/apple/swift-corelibs-foundation/blob/eec4b26deee34edb7664ddd9c1222492a399d122/Sources/Foundation/Process.swift
 This function sets the `readabilityHandler` of inputs and the `writabilityHandler` of outputs,
    so you should not set these yourself after calling `tee`.
 The one exception to this guidance is that you can set the `readabilityHandler` of `input` to `nil` to stop `tee`ing.
 After doing so, the `writeabilityHandler`s of the `output`s will be set to `nil` automatically after all in-progress writes complete,
    but if desired, you could set them to `nil` manually to cancel these writes. However, this may result in some outputs recieving less of the data than others.
 This implementation waits for all outputs to consume a piece of input before more input is read.
 This means that the speed at which your processes read data may be bottlenecked by the speed at which the slowest process reads data,
    but this method also comes with very little memory overhead and is easy to cancel.
 If this is unacceptable for your use case. you may wish to rewrite this with a data deque for each output.
 */
public func tee(from input: Any, into outputs: Any...) {
    /// Get reading and writing handles from the input and outputs respectively.
    guard let input = fileHandleForReading(input) else {
        preconditionFailure(incorrectTypeMessage)
    }
    let outputs: [FileHandle] = outputs.map({
        guard let output = fileHandleForWriting($0) else {
            preconditionFailure(incorrectTypeMessage)
        }
        return output
    })
    
    let writeGroup = DispatchGroup()
    
    input.readabilityHandler = { input in
        let data = input.availableData
        
        /// If the data is empty, EOF reached
        guard !data.isEmpty else {
            /// Stop reading and return
            input.readabilityHandler = nil
            return
        }
        
        for output in outputs {
            /// Tell `writeGroup` to wait on this output.
            writeGroup.enter()
            output.writeabilityHandler = { output in
                /// Synchronously write the data
                output.write(data)
                /// Signal that we do not need to write anymore
                output.writeabilityHandler = nil
                /// Inform `writeGroup` that we are done.
                writeGroup.leave()
            }
        }
        
        /// Wait until all outputs have recieved the data
        writeGroup.wait()
    }
}

/// The message that is passed to `preconditionFailure` when an incorrect type is passed to `tee`.
let incorrectTypeMessage = "Arguments of tee must be either Pipe or FileHandle."

/// Get a file handle for reading from a `Pipe` or the handle itself from a `FileHandle`, or `nil` otherwise.
func fileHandleForReading(_ handle: Any) -> FileHandle? {
    switch handle {
    case let pipe as Pipe:
        return pipe.fileHandleForReading
    case let file as FileHandle:
        return file
    default:
        return nil
    }
}
/// Get a file handle for writing from a `Pipe` or the handle itself from a `FileHandle`, or `nil` otherwise.
func fileHandleForWriting(_ handle: Any) -> FileHandle? {
    switch handle {
    case let pipe as Pipe:
        return pipe.fileHandleForWriting
    case let file as FileHandle:
        return file
    default:
        return nil
    }
}
