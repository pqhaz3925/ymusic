import CommonCrypto
import Foundation

/// Decrypts an `encraw` stream: AES-128-CTR, zero IV, big-endian 128-bit block counter.
///
/// CTR is seekable, so a download resumed at any byte offset starts with the counter at
/// `offset / 16` and throws away the first `offset % 16` keystream bytes.
nonisolated final class StreamCipher {
    private let cryptor: CCCryptorRef

    init?(key: Data, offset: Int64 = 0) {
        guard key.count == kCCKeySizeAES128, offset >= 0 else { return nil }
        var counter = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        withUnsafeBytes(of: UInt64(offset / 16).bigEndian) { counter.replaceSubrange(8..<16, with: $0) }
        var ref: CCCryptorRef?
        let status = key.withUnsafeBytes { k in
            CCCryptorCreateWithMode(CCOperation(kCCDecrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                                    CCPadding(ccNoPadding), counter, k.baseAddress, k.count,
                                    nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &ref)
        }
        guard status == kCCSuccess, let ref else { return nil }
        cryptor = ref
        let skip = Int(offset % 16)
        if skip > 0 { _ = process(Data(count: skip)) }
    }

    deinit { CCCryptorRelease(cryptor) }

    /// Decrypt the next bytes of the stream (any chunk size; state carries over).
    func process(_ data: Data) -> Data {
        guard !data.isEmpty else { return data }
        var out = Data(count: data.count)
        var moved = 0
        let status = data.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                CCCryptorUpdate(cryptor, src.baseAddress, src.count, dst.baseAddress, dst.count, &moved)
            }
        }
        // A stream cipher has no failure mode here short of a programming error.
        precondition(status == kCCSuccess && moved == data.count, "AES-CTR update failed")
        return out
    }

    /// `StreamSource.key`: 16 bytes as hex.
    static func key(hex: String) -> Data? {
        let chars = Array(hex.utf8)
        guard chars.count == kCCKeySizeAES128 * 2 else { return nil }
        var out = Data(capacity: kCCKeySizeAES128)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let hi = Character(UnicodeScalar(chars[i])).hexDigitValue,
                  let lo = Character(UnicodeScalar(chars[i + 1])).hexDigitValue else { return nil }
            out.append(UInt8(hi << 4 | lo))
        }
        return out
    }
}

/// What kind of audio file a stream is. The server labels everything
/// `application/octet-stream` and the URLs have no extension, so the first bytes decide.
nonisolated enum AudioContainer {
    /// How much of the file `type(ofHead:)` wants to see.
    static let headLength = 16

    static let m4a = "com.apple.m4a-audio"   // AVFileType.m4a
    static let flac = "org.xiph.flac"
    static let mp3 = "public.mp3"
    static let aac = "public.aac-audio"

    /// UTI sniffed from the start of the file, or nil when unrecognized.
    static func type(ofHead head: Data) -> String? {
        let b = [UInt8](head.prefix(headLength))
        guard b.count >= 4 else { return nil }
        if b.count >= 8, b[4...7].elementsEqual("ftyp".utf8) { return m4a }
        if b[0...3].elementsEqual("fLaC".utf8) { return flac }
        if b[0...2].elementsEqual("ID3".utf8) { return mp3 }
        if b[0] == 0xFF, b[1] & 0xE0 == 0xE0 {
            // MPEG sync word. Layer bits 00 mean ADTS (raw AAC), anything else is MPEG audio.
            return b[1] & 0xF6 == 0xF0 ? aac : mp3
        }
        return nil
    }

    /// Best guess from the codec name the API reports (`flac-mp4`, `aac`, `mp3`, …).
    static func type(forCodec codec: String) -> String? {
        switch codec {
        case let c where c.hasSuffix("-mp4"): m4a
        case "flac": flac
        case "mp3": mp3
        case "aac", "he-aac": aac
        default: nil
        }
    }

    static func fileExtension(for type: String) -> String {
        switch type {
        case flac: "flac"
        case mp3: "mp3"
        case aac: "aac"
        default: "m4a"
        }
    }
}
