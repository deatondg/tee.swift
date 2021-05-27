# tee.swift

`tee`-like functionality for `Pipe` and `FileHandle` in Swift. Connect one pipe to many!

# Usage

This library exports a single function (well, two) which reads data from an input `TeeReadable` (think  a `Pipe` or `FileHandle`) and writes it to multiple output `TeeWriteable`s. 
When used with `Process`, this enables sending the output of one process to many or capturing the output of a process and sending it to the standard output simultaneously. 
```swift
public func tee(from input: TeeReadable, into outputs: TeeWriteable...)
public func tee(from input: TeeReadable, into outputs: [TeeWriteable])
```

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
        .package(name: "tee", url: "https://github.com/deatondg/tee.swift", from: "2.0.0"),
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

# Documentation

```swift
public func tee(from input: TeeReadable, into outputs: TeeWriteable...)
public func tee(from input: TeeReadable, into outputs: [TeeWriteable])
```
`tee` duplicates the data from `input` into each of the `outputs`.
Generally, the arguments to `tee` should be `Pipe`s or `FileHandles` like the `standardInput`/`standardOutput`/`standardError` properties of `Process`.
The `fileHandleForReading` of `input` is used to gather data which is then written to the `fileHandleForWriting` of the `outputs`.
When the input sends an EOF (observed as a length 0 read), the handles of `input` and `outputs` are closed if their `teeShouldCloseForReadingOnEOF` or `shouldCloseForWritingOnEOF` properties respectively are `true`.
`tee` sets the `readabilityHandler` of inputs and the `writeabilityHandler` of outputs, so you should not set these yourself after calling `tee`.
The one exception to this guidance is that you can set the `readabilityHandler` of the input's handle to `nil` to stop `tee`ing.
After doing so, the `writeabilityHandler`s of the outputs will be set to `nil` automatically after all in-progress writes complete, but if desired, you could set them to `nil` manually to cancel these writes although this may result in some outputs recieving less of the data than others.
This implementation waits for all outputs to consume a piece of input before more input is read.
This means that the speed at which your processes read data may be bottlenecked by the speed at which the slowest process reads data, but this method also comes with very little memory overhead and is easy to cancel.
If this is unacceptable for your use case, you may wish to rewrite this with a data deque for each output.

<br/>

```swift
public protocol TeeReadable {
    var fileHandleForReading: FileHandle { get }
    var teeShouldCloseForReadingOnEOF: Bool { get }
}
```
This protocol describes a possible `input` argument of the `tee` function.
The `fileHandleForReading` of inputs is used to gather data which is then wrriten to the `fileHandleForWriting` of the outputs.
If `teeShouldCloseForReadingOnEOF` is `true`, the `fileHandleForReading` will be closed once the it sends an EOF.
These getters are called once at the beginning of `tee` and never read from again.

<br/>

```swift
public protocol TeeWriteable {
    var fileHandleForWriting: FileHandle { get }
    var teeShouldCloseForWritingOnEOF: Bool { get }
}
```
This protocol describes the `outputs` arguments of the `tee` function.
The `fileHandleForReading` of inputs is used to gather data which is then wrriten to the `fileHandleForWriting` of the outputs.
If `teeShouldCloseForWritingOnEOF` is `true`, the `fileHandleForWriting` will be closed once the it sends an EOF.
These getters are called once at the beginning of `tee` and never read from again.

<br/>

```swift
public typealias Teeable = TeeReadable & TeeWriteable
```
A simple typealias for a type which can be any argument to `tee`

<br/>

```swift
extension FileHandle: Teeable
```
`FileHandle` is made to conform to `Teeable` in the simplest way possible: it's file handles are just itself.
By default, `tee` will _not_ close `FileHandle`s on EOF, so you must override this property if you would like different behavior.
This is so that it is easy to work with `FileHandle.standardInput`/`.standardOutput`/`.standardError`, which should not be closed.

<br/>

```swift
extension Pipe: Teeable
```
`Pipe` essentially already conforms to `Teeable`.
By default, `tee` will close `Pipe`s on EOF for writing but _not_ for reading, so you must override this property if you would like different behavior.
This is so that it is easy to integrate `tee` into existing workflows involving `Process`.
As far as I know, there is no way to create a `Pipe` which does not own its reading handle, so you should not overwrite `teeShouldCloseForReadingOnEOF`.

<br/>

```swift
extension TeeReadable {
    public func teeCloseForReadingOnEOF(_ shouldCloseForReadingOnEOF: Bool = true) -> TeeCloseForReadingOnEOF<Self>
}
```
A convience method on `TeeReadable` to change `teeShouldCloseForReadingOnEOF`.
Calling `t.teeCloseForReadingOnEOF(a)` for some `t: TeeReadable` and `a: Bool` returns a `TeeReadable` with a handle which is that of `t` and a `teeShouldCloseForReadingOnEOF` which is `a`.

<br/>

```swift
extension TeeWriteable {
    public func teeCloseForWritingOnEOF(_ shouldCloseForWritingOnEOF: Bool = true) -> TeeCloseForWritingOnEOF<Self> 
}
```
A convience method on `TeeWriteable` to change `teeShouldCloseForWritingOnEOF`.
Calling `t.teeCloseForWritingOnEOF(a)` for some `t: TeeWriteable` and `a: Bool` returns a `TeeWriteable` with a handle which is that of `t` and a `teeShouldCloseForWritingOnEOF` which is `a`.

<br/>

```swift
extension TeeReadable where Self: TeeWriteable {
    public func teeCloseOnEOF(forReading shouldCloseForReadingOnEOF: Bool = false, forWriting shouldCloseForWritingOnEOF: Bool = true) -> TeeCloseOnEOF<Self>
}
```
A convience method on `Teeable` to change `teeShouldCloseForReadingOnEOF` and`teeShouldCloseForWritingOnEOF` simultaneously.
Calling `t.teeCloseForOnEOF(forReading: a, forWriting: b)` for some `t: Teeable`, `a: Bool`, and `b: Bool` returns a `Teeable` with handles which are that of `t`, a `teeShouldCloseForReadingOnEOF` which is `a`, and a `teeShouldCloseForWritingOnEOF` which is `b`.
