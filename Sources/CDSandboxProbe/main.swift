import Foundation
import OpticalDiscBridge

var deviceCount: Int32 = 0
guard SBOpticalDiscCopyDevices(nil, 0, &deviceCount) == 0, deviceCount > 0 else {
    FileHandle.standardError.write(Data("NO_DEVICE\n".utf8))
    exit(2)
}
var devices = [SBOpticalDiscDevice](repeating: SBOpticalDiscDevice(), count: Int(deviceCount))
guard SBOpticalDiscCopyDevices(&devices, deviceCount, &deviceCount) == 0 else { exit(3) }

let deviceID = withUnsafeBytes(of: devices[0].bsdName) { raw in
    String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
}
var entryCount: Int32 = 0
var leadOut: Int64 = 0
let tocStatus = deviceID.withCString {
    SBOpticalDiscReadTOC($0, nil, 0, &entryCount, &leadOut)
}
guard tocStatus == 0, entryCount > 0 else {
    FileHandle.standardError.write(Data("TOC_DENIED device=\(deviceID) status=\(tocStatus)\n".utf8))
    exit(4)
}
var entries = [SBOpticalTOCEntry](repeating: SBOpticalTOCEntry(), count: Int(entryCount))
guard deviceID.withCString({
    SBOpticalDiscReadTOC($0, &entries, entryCount, &entryCount, &leadOut)
}) == 0, let first = entries.prefix(Int(entryCount)).first(where: { ($0.control & 0x04) == 0 }) else {
    exit(5)
}
var sector = Data(count: Int(SB_CDDA_SECTOR_BYTES))
let sectorCapacity = sector.count
var bytesRead: Int32 = 0
let readStatus = sector.withUnsafeMutableBytes { raw in
    deviceID.withCString {
        SBOpticalDiscReadCDDASectors(
            $0,
            first.startSector,
            1,
            raw.bindMemory(to: UInt8.self).baseAddress,
            Int32(sectorCapacity),
            &bytesRead
        )
    }
}
guard readStatus == 0, bytesRead == SB_CDDA_SECTOR_BYTES else {
    FileHandle.standardError.write(Data("SECTOR_DENIED device=\(deviceID) status=\(readStatus)\n".utf8))
    exit(6)
}

let benchmark = CommandLine.arguments.contains("--benchmark")
if benchmark {
    let sectorsPerRead: Int32 = 16
    let iterations = 75
    var block = Data(count: Int(sectorsPerRead) * Int(SB_CDDA_SECTOR_BYTES))
    let blockCapacity = block.count
    let started = ContinuousClock.now
    for iteration in 0..<iterations {
        var blockBytes: Int32 = 0
        let status = block.withUnsafeMutableBytes { raw in
            deviceID.withCString {
                SBOpticalDiscReadCDDASectors(
                    $0,
                    first.startSector + Int64(iteration * Int(sectorsPerRead)),
                    sectorsPerRead,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    Int32(blockCapacity),
                    &blockBytes
                )
            }
        }
        guard status == 0, blockBytes == sectorsPerRead * SB_CDDA_SECTOR_BYTES else {
            FileHandle.standardError.write(
                Data("BENCHMARK_READ_FAILED iteration=\(iteration) status=\(status)\n".utf8)
            )
            exit(7)
        }
    }
    let elapsed = started.duration(to: .now)
    print(
        "PASS device=\(deviceID) tracks=\(entryCount) leadOut=\(leadOut) "
            + "bytes=\(bytesRead) benchmarkReads=\(iterations) elapsed=\(elapsed)"
    )
} else {
    print("PASS device=\(deviceID) tracks=\(entryCount) leadOut=\(leadOut) bytes=\(bytesRead)")
}
