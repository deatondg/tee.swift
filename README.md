# tee.swift

`tee`-like functionality for `Pipe` and `FileHandle` in Swift. Connect one pipe to many!

# Usage

This library exports a single function (well, two) which reads data from an input `Pipe` or `FileHandle` and writes it to multiple output `Pipe`s or `FileHandle`s. When used with `Process`, this enables sending the output of one process to many or capturing the output of a process and sending it to the standard output simultaneously. 
```swift
public func tee(from input: Any, into outputs: Any...)
public func tee(from input: Any, into outputs: [Any])
```
Following the precedent of `standardInput`/`standardOutput`/`standardError` in [`Process` from `Foundation`](https://github.com/apple/swift-corelibs-foundation/blob/eec4b26deee34edb7664ddd9c1222492a399d122/Sources/Foundation/Process.swift), this function accepts the type `Any`, but throws a precondition failure if the arguments are not of type `Pipe` or `FileHandle`.

When `input` sends an EOF (write of length 0), the `outputs` file handles are closed, so only output to handles you own.

This function sets the `readabilityHandler` of inputs and the `writabilityHandler` of outputs, so you should not set these yourself after calling `tee`. The one exception to this guidance is that you can set the `readabilityHandler` of `input` to `nil` to stop `tee`ing. After doing so, the `writeabilityHandler`s of the `output`s will be set to `nil` automatically after all in-progress writes complete, but if desired, you could set them to `nil` manually to cancel these writes. However, this may result in some outputs recieving less of the data than others.

This implementation waits for all outputs to consume a piece of input before more input is read. This means that the speed at which your processes read data may be bottlenecked by the speed at which the slowest process reads data, but this method also comes with very little memory overhead and is easy to cancel. If this is unacceptable for your use case. you may wish to rewrite this with a data deque for each output.

To import this function, add this library as a SwiftPM dependency.
```swift
// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "Example",
    products: [
        .library(
            name: "ExampleTarget",
            targets: ["ExampleTarget"]),
    ],
    dependencies: [
        .package(name: "tee", url: "https://github.com/deatondg/tee.swift", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ExampleTarget",
            dependencies: ["tee"]),
    ]
)
```

# Examples

Capture output and send it to the console:
```swift
import Foundation
import tee

/// Create a pipe to capture the output of a process.
let processOutput = Pipe()

/// Create another pipe to recieve output from tee.
let teeOutput = Pipe()

/// Use tee to send to process output into the pipe we created and standard output simultaneously.
tee(from: processOutput, into: teeOutput, FileHandle.standardOutput)

/// Run a process.
let exampleProcess = Process()
exampleProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
exampleProcess.arguments = ["-c", "echo hello from tee!"]
exampleProcess.standardOutput = processOutput

try! exampleProcess.run()

/// Confirm the output is what we expect it to be.
let output = String(data: try! teeOutput.fileHandleForReading.readToEnd()!, encoding: .utf8)!
assert(output == "hello from tee!\n")
```

Split the output of a process into two pipes:
```swift
/// Create a process like usual.
let processOutput = Pipe()
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/sh")
process.arguments = ["-c", "echo example123"]
process.standardOutput = processOutput

/// Create two pipes to recieve the output.
let output1 = Pipe()
let output2 = Pipe()

/// Use tee to send the output from the process into both pipes.
tee(from: processOutput, into: output1, output2)

/// Run the process.
try process.run()
process.waitUntilExit()

/// Confirm the output is what we expect it to be.
assert(String(data: output1.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) == "example123\n")
assert(String(data: output2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) == "example123\n")
```

Send the same input to two processes simultaneously:
```swift
/// Create two processes like usual.
let cat1 = Process()
let cat2 = Process()

cat1.executableURL = URL(fileURLWithPath: "/bin/cat")
cat2.executableURL = URL(fileURLWithPath: "/bin/cat")

let catInput1 = Pipe()
let catInput2 = Pipe()
let catOutput1 = Pipe()
let catOutput2 = Pipe()

cat1.standardInput = catInput1
cat2.standardInput = catInput2

cat1.standardOutput = catOutput1
cat2.standardOutput = catOutput2

/// Create a pipe to recieve input.
let input = Pipe()

/// Use tee to send output from this pipe into both processes.
tee(from: input, into: catInput1, catInput2)

/// Run the processes.
try cat1.run()
try cat2.run()

/// Write some data to both processes, then close to send EOF.
let inputHandle = input.fileHandleForWriting

let message = "you can send the same data twice"
let data = message.data(using: .utf8)!

inputHandle.write(data)
inputHandle.closeFile()

/// Confirm the output from both processes is what we expect it to be.
assert(String(data: catOutput1.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) == message)
assert(String(data: catOutput2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) == message)
```
