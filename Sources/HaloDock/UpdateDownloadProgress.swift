import Foundation

/// A session delegate (rather than a completion-handler task) receives byte progress.
final class UpdateDownloadProgress:NSObject,URLSessionDownloadDelegate,@unchecked Sendable {
    let expected:Int64
    let onProgress:@Sendable(Double)->Void
    private let lock=NSLock()
    private var continuation:CheckedContinuation<(URL,URLResponse),Error>?
    private var activeSession:URLSession?
    private var completedFile:URL?
    private var fileError:Error?
    init(expected:Int64,onProgress:@escaping @Sendable(Double)->Void) {self.expected=expected;self.onProgress=onProgress}

    func download(for request:URLRequest) async throws -> (URL,URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {continuation.resume(throwing:CancellationError());return}
                let session=URLSession(configuration:.default,delegate:self,delegateQueue:nil)
                lock.lock();self.continuation=continuation;activeSession=session;lock.unlock()
                session.downloadTask(with:request).resume()
            }
        } onCancel: {
            self.lock.lock();let session=self.activeSession;self.lock.unlock()
            session?.invalidateAndCancel()
        }
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {
        let destination=FileManager.default.temporaryDirectory.appendingPathComponent("HaloDockDownload-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.moveItem(at:location,to:destination)
            lock.lock();completedFile=destination;lock.unlock()
        } catch {lock.lock();fileError=error;lock.unlock()}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        lock.lock()
        let continuation=self.continuation,file=completedFile,failure=error ?? fileError
        self.continuation=nil;activeSession=nil;completedFile=nil
        lock.unlock()
        if let failure {
            if let file {try? FileManager.default.removeItem(at:file)}
            continuation?.resume(throwing:failure)
        } else if let file,let response=task.response {
            continuation?.resume(returning:(file,response))
        } else {continuation?.resume(throwing:URLError(.cannotCreateFile))}
        session.finishTasksAndInvalidate()
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        let total=totalBytesExpectedToWrite>0 ? totalBytesExpectedToWrite:expected
        if total>0 {onProgress(min(1,Double(totalBytesWritten)/Double(total)))}
    }
}
