import Foundation

/// Low-level JSON IPC transport for a running mpv instance.
///
/// Connects to mpv's `--input-ipc-server` Unix domain socket, sends newline-delimited
/// JSON commands, and dispatches newline-delimited JSON replies/events back to the caller.
public final class MPVIPC {
    private let socketPath: String
    private var fd: Int32 = -1
    private let writeQueue = DispatchQueue(label: "dev.solfin.mpv.write")
    private var readThread: Thread?
    private var nextRequestId = 1
    private let idLock = NSLock()

    /// Called on a background thread for every decoded message from mpv.
    public var onMessage: (([String: Any]) -> Void)?
    /// Called when the socket closes (mpv exited or connection dropped).
    public var onClose: (() -> Void)?

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    /// Poll for the socket to appear (mpv creates it a beat after launch), then connect.
    /// Returns false if it never appears within `timeout`.
    @discardableResult
    public func connect(timeout: TimeInterval = 5.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: socketPath), openSocket() {
                startReadLoop()
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private func openSocket() -> Bool {
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return false }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(s); return false
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    dst.update(from: src.baseAddress!, count: src.count)
                }
            }
        }

        let result = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                Foundation.connect(s, sp, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { close(s); return false }
        fd = s
        return true
    }

    private func startReadLoop() {
        let thread = Thread { [weak self] in
            guard let self else { return }
            var buffer = Data()
            let chunkSize = 4096
            var chunk = [UInt8](repeating: 0, count: chunkSize)

            while self.fd >= 0 {
                let n = read(self.fd, &chunk, chunkSize)
                if n <= 0 { break }
                buffer.append(contentsOf: chunk[0..<n])

                // Split on newlines; each line is a JSON object.
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                    buffer.removeSubrange(buffer.startIndex...nl)
                    guard !lineData.isEmpty,
                          let obj = try? JSONSerialization.jsonObject(with: lineData),
                          let dict = obj as? [String: Any] else { continue }
                    self.onMessage?(dict)
                }
            }
            self.onClose?()
        }
        thread.name = "dev.solfin.mpv.read"
        thread.start()
        readThread = thread
    }

    /// Serialize a command array + request_id into a newline-terminated JSON line.
    /// Pure and side-effect-free so it can be unit tested.
    public static func encodeCommand(_ args: [Any], requestId: Int) -> Data? {
        let payload: [String: Any] = ["command": args, "request_id": requestId]
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        data.append(0x0A)
        return data
    }

    /// Build the argument array for a `loadfile` command (pure; unit tested).
    public static func loadFileArgs(url: String, startSeconds: Double?, mediaTitle: String? = nil) -> [Any] {
        var options: [String] = []
        if let start = startSeconds, start > 0 {
            options.append("start=\(Int(start))")
        }
        if let mediaTitle, !mediaTitle.isEmpty {
            options.append("force-media-title=\(mediaTitle)")
        }
        guard !options.isEmpty else { return ["loadfile", url, "replace"] }
        return ["loadfile", url, "replace", 0] + options
    }

    /// Send a command array, e.g. `["loadfile", url]`. Returns the request_id used.
    @discardableResult
    public func command(_ args: [Any]) -> Int {
        idLock.lock()
        let requestId = nextRequestId
        nextRequestId += 1
        idLock.unlock()

        guard let line = Self.encodeCommand(args, requestId: requestId) else { return requestId }
        writeQueue.async { [weak self] in
            guard let self, self.fd >= 0 else { return }
            line.withUnsafeBytes { raw in
                _ = write(self.fd, raw.baseAddress, raw.count)
            }
        }
        return requestId
    }

    public func observeProperty(_ name: String, id: Int) {
        command(["observe_property", id, name])
    }

    public func setProperty(_ name: String, _ value: Any) {
        command(["set_property", name, value])
    }

    /// Build the `sub-add` arguments used for Jellyfin sidecars.
    public static func addSubtitleArgs(url: String, title: String? = nil,
                                       language: String? = nil) -> [Any] {
        ["sub-add", url, "auto", title ?? "", language ?? ""]
    }

    /// Add a subtitle without selecting it. Jellyfin sidecars are loaded this way,
    /// then matched to mpv's assigned track ID through `track-list`.
    @discardableResult
    public func addSubtitle(url: String, title: String? = nil,
                            language: String? = nil) -> Int {
        command(Self.addSubtitleArgs(url: url, title: title, language: language))
    }

    public func getProperty(_ name: String) -> Int {
        command(["get_property", name])
    }

    public func loadFile(_ url: String, startSeconds: Double? = nil, mediaTitle: String? = nil) {
        command(Self.loadFileArgs(url: url, startSeconds: startSeconds, mediaTitle: mediaTitle))
    }

    public func scriptMessage(_ args: [Any]) {
        command(["script-message"] + args)
    }

    public func quit() {
        command(["quit"])
    }

    public func disconnect() {
        let old = fd
        fd = -1
        if old >= 0 { close(old) }
    }
}
