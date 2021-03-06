// Copyright 2019, Emmanouil Antonios Platanios. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not
// use this file except in compliance with the License. You may obtain a copy of
// the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations under
// the License.

import Foundation
import TensorFlow

#if os(Linux)
import FoundationNetworking
#endif

public typealias TensorFlowSeed = (graph: Int32, op: Int32)

public enum ReinforcementLearningError: Error {
  case renderingError(String)
}

public struct Empty: Differentiable, KeyPathIterable {
  public init() {}
}

public protocol Copyable {
  func copy() -> Self
}

public extension Encodable {
  func json(pretty: Bool = true) throws -> String {
    let encoder = JSONEncoder()
    if pretty {
      encoder.outputFormatting = .prettyPrinted
    }
    let data = try encoder.encode(self)
    return String(data: data, encoding: .utf8)!
  }
}

public extension Decodable {
  init(fromJson json: String) throws {
    let jsonDecoder = JSONDecoder()
    self = try jsonDecoder.decode(Self.self, from: json.data(using: .utf8)!)
  }
}

/// Downloads the file at `url` to `path`, if `path` does not exist.
///
/// - Parameters:
///     - from: URL to download data from.
///     - to: Destination file path.
///
/// - Returns: Boolean value indicating whether a download was
///     performed (as opposed to not needed).
public func maybeDownload(from url: URL, to destination: URL) throws {
  if !FileManager.default.fileExists(atPath: destination.path) {
    // Create any potentially missing directories.
    try FileManager.default.createDirectory(
      atPath: destination.deletingLastPathComponent().path,
      withIntermediateDirectories: true)

    // Create the URL session that will be used to download the dataset.
    let semaphore = DispatchSemaphore(value: 0)
    let delegate = DataDownloadDelegate(destinationFileUrl: destination, semaphore: semaphore)
    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

    // Download the data to a temporary file and then copy that file to
    // the destination path.
    print("Downloading \(url).")
    let task = session.downloadTask(with: url)
    task.resume()

    // Wait for the download to finish.
    semaphore.wait()
  }
}

internal class DataDownloadDelegate: NSObject, URLSessionDownloadDelegate {
  let destinationFileUrl: URL
  let semaphore: DispatchSemaphore
  let numBytesFrequency: Int64

  internal var logCount: Int64 = 0

  init(
    destinationFileUrl: URL,
    semaphore: DispatchSemaphore,
    numBytesFrequency: Int64 = 1024 * 1024
  ) {
    self.destinationFileUrl = destinationFileUrl
    self.semaphore = semaphore
    self.numBytesFrequency = numBytesFrequency
  }

  internal func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) -> Void {
    if (totalBytesWritten / numBytesFrequency > logCount) {
      let mBytesWritten = String(format: "%.2f", Float(totalBytesWritten) / (1024 * 1024))
      if totalBytesExpectedToWrite > 0 {
        let mBytesExpectedToWrite = String(
          format: "%.2f", Float(totalBytesExpectedToWrite) / (1024 * 1024))
        print("Downloaded \(mBytesWritten) MBs out of \(mBytesExpectedToWrite).")
      } else {
        print("Downloaded \(mBytesWritten) MBs.")
      }
      logCount += 1
    }
  }

  internal func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) -> Void {
    logCount = 0
    do {
      try FileManager.default.moveItem(at: location, to: destinationFileUrl)
    } catch (let writeError) {
      print("Error writing file \(location.path) : \(writeError)")
    }
    print("The file was downloaded successfully to \(location.path).")
    semaphore.signal()
  }
}
