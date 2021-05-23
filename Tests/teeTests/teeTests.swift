    import XCTest
    @testable import tee

    final class teeTests: XCTestCase {
        func testFileHandleForReading() {
            let pipe = Pipe()
            XCTAssertEqual(fileHandleForReading(pipe), pipe.fileHandleForReading)
            XCTAssertEqual(fileHandleForReading(FileHandle.standardInput), FileHandle.standardInput)
            XCTAssertEqual(fileHandleForReading(FileHandle.nullDevice), FileHandle.nullDevice)
            XCTAssertNil(fileHandleForReading("test"))
        }
        
        func testFileHandleForWriting() {
            let pipe = Pipe()
            XCTAssertEqual(fileHandleForWriting(pipe), pipe.fileHandleForWriting)
            XCTAssertEqual(fileHandleForWriting(FileHandle.standardOutput), FileHandle.standardOutput)
            XCTAssertEqual(fileHandleForWriting(FileHandle.nullDevice), FileHandle.nullDevice)
            XCTAssertNil(fileHandleForWriting("test"))
        }
        
        func testTee() {
            let input = Pipe()
            let output1 = Pipe()
            let output2 = Pipe()
            
            let inputHandle = input.fileHandleForWriting
            let outputHandle1 = output1.fileHandleForReading
            let outputHandle2 = output2.fileHandleForReading
            
            tee(from: input, into: output1, output2)
            
            let message1 = "test123"
            let data1 = message1.data(using: .utf8)!
            inputHandle.write(data1)
            
            XCTAssertEqual(String(data: outputHandle1.readData(ofLength: data1.count), encoding: .utf8), message1)
            XCTAssertEqual(String(data: outputHandle2.readData(ofLength: data1.count), encoding: .utf8), message1)
            
            let message2 = "lhasdlkhasdljhasldasdfysdvjwe;iofhAOSIh;erhipuhdlahbdlkncsaheagf"
            let data2 = message2.data(using: .utf8)!
            inputHandle.write(data2)
            
            XCTAssertEqual(String(data: outputHandle1.readData(ofLength: data2.count), encoding: .utf8), message2)
            XCTAssertEqual(String(data: outputHandle2.readData(ofLength: data2.count), encoding: .utf8), message2)
            
            let message3 = "onetwothreedoreme"
            let data3 = message3.data(using: .utf8)!
            
            let message4 = "teeisuseful"
            let data4 = message4.data(using: .utf8)!
            
            inputHandle.write(data3)
            inputHandle.write(data4)
            
            XCTAssertEqual(String(data: outputHandle1.readData(ofLength: data3.count + data4.count), encoding: .utf8), message3 + message4)
            XCTAssertEqual(String(data: outputHandle2.readData(ofLength: data3.count + data4.count), encoding: .utf8), message3 + message4)
            
            inputHandle.closeFile()
            
            XCTAssert(outputHandle1.readDataToEndOfFile().isEmpty)
            XCTAssert(outputHandle2.readDataToEndOfFile().isEmpty)
        }
        
        func testTeeOutOfProcess() throws {
            let processOutput = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "echo trust but verify"]
            process.standardOutput = processOutput
            
            let output1 = Pipe()
            let output2 = Pipe()
            
            tee(from: processOutput, into: output1, output2)
            
            try process.run()
            process.waitUntilExit()
            
            XCTAssertEqual(String(data: output1.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "trust but verify\n")
            XCTAssertEqual(String(data: output2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "trust but verify\n")
        }
        
        func testTeeIntoProcess() throws {
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
            
            let input = Pipe()
            
            tee(from: input, into: catInput1, catInput2)
            
            try cat1.run()
            try cat2.run()
            
            let inputHandle = input.fileHandleForWriting
            
            let message = "you can send the same data twice"
            let data = message.data(using: .utf8)!
            
            inputHandle.write(data)
            inputHandle.closeFile()
            
            XCTAssertEqual(String(data: catOutput1.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), message)
            XCTAssertEqual(String(data: catOutput2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), message)
        }
    }
