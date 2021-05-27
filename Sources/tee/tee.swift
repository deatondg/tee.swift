import Foundation

/**
 `tee` duplicates the data from `input` into each of the `outputs`.
 Generally, the arguments to `tee` should be `Pipe`s or `FileHandles` like the
    `standardInput`/`standardOutput`/`standardError` properties on `Process`.
 The `fileHandleForReading` of `input` is used to gather data which is then written to the `fileHandleForWriting` of the `outputs`.
 When the input sends an EOF (observed as a length 0 read), the handles of `input` and `outputs` are closed if their
    `teeShouldCloseForReadingOnEOF` or `shouldCloseForWritingOnEOF` properties respectively are `true`.
 `tee` sets the `readabilityHandler` of inputs and the `writeabilityHandler` of outputs, so you should not set these yourself after calling `tee`.
 The one exception to this guidance is that you can set the `readabilityHandler` of the input's handle to `nil` to stop `tee`ing.
 After doing so, the `writeabilityHandler`s of the outputs will be set to `nil` automatically after all in-progress writes complete,
    but if desired, you could set them to `nil` manually to cancel these writes although this may result in some outputs recieving less of the data than others.
 This implementation waits for all outputs to consume a piece of input before more input is read.
 This means that the speed at which your processes read data may be bottlenecked by the speed at which the slowest process reads data,
    but this method also comes with very little memory overhead and is easy to cancel.
 If this is unacceptable for your use case, you may wish to rewrite this with a data deque for each output.
 The `TeeReadable` and `TeeWriteable` types are defined below, followed by some convenience methods, then the non-variadic implementation of `tee`.
 */
public func tee(from input: TeeReadable, into outputs: TeeWriteable...) {
    tee(from: input, into: outputs)
}

/**
 This protocol describes a possible `input` argument of the `tee` function.
 The `fileHandleForReading` of inputs is used to gather data which is then wrriten to the `fileHandleForWriting` of the outputs.
 If `teeShouldCloseForReadingOnEOF` is `true`, the `fileHandleForReading` will be closed once the it sends an EOF.
 These getters are called once at the beginning of `tee` and never read from again.
 */
public protocol TeeReadable {
    var fileHandleForReading: FileHandle { get }
    var teeShouldCloseForReadingOnEOF: Bool { get }
}
/**
 This protocol describes the `outputs` arguments of the `tee` function.
 The `fileHandleForReading` of inputs is used to gather data which is then wrriten to the `fileHandleForWriting` of the outputs.
 If `teeShouldCloseForWritingOnEOF` is `true`, the `fileHandleForWriting` will be closed once the it sends an EOF.
 These getters are called once at the beginning of `tee` and never read from again.
 */
public protocol TeeWriteable {
    var fileHandleForWriting: FileHandle { get }
    var teeShouldCloseForWritingOnEOF: Bool { get }
}
/**
 A simple typealias for a type which can be any argument to `tee`
 */
public typealias Teeable = TeeReadable & TeeWriteable

/**
 `FileHandle` is made to conform to `Teeable` in the simplest way possible: it's file handles are just itself.
 By default, `tee` will _not_ close `FileHandle`s on EOF, so you must override this property if you would like different behavior.
 This is so that it is easy to work with `FileHandle.standardInput`/`.standardOutput`/`.standardError`, which should not be closed.
 */
extension FileHandle: Teeable {
    public var fileHandleForReading: FileHandle { self }
    public var teeShouldCloseForReadingOnEOF: Bool { false }
    public var fileHandleForWriting: FileHandle { self }
    public var teeShouldCloseForWritingOnEOF: Bool { false }
}
/**
 `Pipe` essentially already conforms to `Teeable`.
 By default, `tee` will close `Pipe`s on EOF for writing but _not_ for reading, so you must override this property if you would like different behavior.
 This is so that it is easy to integrate `tee` into existing workflows involving `Process`.
 As far as I know, there is no way to create a `Pipe` which does not own its reading handle, so you should not overwrite `teeShouldCloseForReadingOnEOF`.
 */
extension Pipe: Teeable {
    public var teeShouldCloseForReadingOnEOF: Bool { false }
    public var teeShouldCloseForWritingOnEOF: Bool { true }
}

/**
 A convience method on `TeeReadable` to change `teeShouldCloseForReadingOnEOF`.
 Calling `t.teeCloseForReadingOnEOF(a)` for some `t: TeeReadable` and `a: Bool` returns a `TeeReadable`
    with a handle which is that of `t` and a `teeShouldCloseForReadingOnEOF` which is `a`.
 */
extension TeeReadable {
    public func teeCloseForReadingOnEOF(_ shouldCloseForReadingOnEOF: Bool = true) -> TeeCloseForReadingOnEOF<Self> {
        TeeCloseForReadingOnEOF(self, shouldCloseForReadingOnEOF)
    }
}
public final class TeeCloseForReadingOnEOF<T: TeeReadable>: TeeReadable {
    private let t: T
    public let teeShouldCloseForReadingOnEOF: Bool
    public init(_ t: T, _ shouldCloseForReadingOnEOF: Bool = true) {
        self.t = t
        self.teeShouldCloseForReadingOnEOF = shouldCloseForReadingOnEOF
    }
    public var fileHandleForReading: FileHandle { t.fileHandleForReading }
}
/**
 A convience method on `TeeWriteable` to change `teeShouldCloseForWritingOnEOF`.
 Calling `t.teeCloseForWritingOnEOF(a)` for some `t: TeeWriteable` and `a: Bool` returns a `TeeWriteable`
    with a handle which is that of `t` and a `teeShouldCloseForWritingOnEOF` which is `a`.
 */
extension TeeWriteable {
    public func teeCloseForWritingOnEOF(_ shouldCloseForWritingOnEOF: Bool = true) -> TeeCloseForWritingOnEOF<Self> {
        TeeCloseForWritingOnEOF(self, shouldCloseForWritingOnEOF)
    }
}
public final class TeeCloseForWritingOnEOF<T: TeeWriteable>: TeeWriteable {
    private let t: T
    public let teeShouldCloseForWritingOnEOF: Bool
    public init(_ t: T, _ shouldCloseForWritingOnEOF: Bool = true){
        self.t = t
        self.teeShouldCloseForWritingOnEOF = shouldCloseForWritingOnEOF
    }
    public var fileHandleForWriting: FileHandle { t.fileHandleForWriting }
}
/**
 A convience method on `Teeable` to change `teeShouldCloseForReadingOnEOF` and`teeShouldCloseForWritingOnEOF` simultaneously.
 Calling `t.teeCloseForOnEOF(forReading: a, forWriting: b)` for some `t: Teeable`, `a: Bool`, and `b: Bool` returns a `Teeable`
    with handles which are that of `t`, a `teeShouldCloseForReadingOnEOF` which is `a`, and a `teeShouldCloseForWritingOnEOF` which is `b`.
 */
extension TeeReadable where Self: TeeWriteable {
    public func teeCloseOnEOF(forReading shouldCloseForReadingOnEOF: Bool = false, forWriting shouldCloseForWritingOnEOF: Bool = true) -> TeeCloseOnEOF<Self> {
        TeeCloseOnEOF(self, forReading: shouldCloseForReadingOnEOF, forWriting: shouldCloseForWritingOnEOF)
    }
}
public final class TeeCloseOnEOF<T: Teeable>: Teeable {
    private let t: T
    public let teeShouldCloseForReadingOnEOF: Bool
    public let teeShouldCloseForWritingOnEOF: Bool
    public init(_ t: T, forReading shouldCloseForReadingOnEOF: Bool = false, forWriting shouldCloseForWritingOnEOF: Bool = true) {
        self.t = t
        self.teeShouldCloseForReadingOnEOF = shouldCloseForReadingOnEOF
        self.teeShouldCloseForWritingOnEOF = shouldCloseForWritingOnEOF
    }
    public var fileHandleForReading: FileHandle { t.fileHandleForReading }
    public var fileHandleForWriting: FileHandle { t.fileHandleForWriting }
}

/**
 Here lies the actual implementation of `tee`.
 This has the same properties as the variadic `tee` (as that one just calls this one), so look there for documentation.
 */
public func tee(from input: TeeReadable, into outputs: [TeeWriteable]) {
    /// Get reading and writing handles from the input and outputs respectively and whether or not we should close them on EOF.
    let input = (handle: input.fileHandleForReading, shouldCloseOnEOF: input.teeShouldCloseForReadingOnEOF)
    let outputs = outputs.map({ (handle: $0.fileHandleForWriting, shouldCloseOnEOF: $0.teeShouldCloseForWritingOnEOF) })
    
    let writeGroup = DispatchGroup()
    
    input.handle.readabilityHandler = { inputHandle in
        let data = inputHandle.availableData
        
        /// If the data is empty, EOF reached
        guard !data.isEmpty else {
            /// Close all the outputs
            for (outputHandle, shouldCloseOnEOF) in outputs where shouldCloseOnEOF {
                outputHandle.closeFile()
            }
            /// Stop reading and return
            inputHandle.readabilityHandler = nil
            if input.shouldCloseOnEOF {
                inputHandle.closeFile()
            }
            return
        }
        
        for (outputHandle, _) in outputs {
            /// Tell `writeGroup` to wait on this output.
            writeGroup.enter()
            outputHandle.writeabilityHandler = { outputHandle in
                /// Synchronously write the data
                outputHandle.write(data)
                /// Signal that we do not need to write anymore
                outputHandle.writeabilityHandler = nil
                /// Inform `writeGroup` that we are done.
                writeGroup.leave()
            }
        }
        
        /// Wait until all outputs have recieved the data
        writeGroup.wait()
    }
}
