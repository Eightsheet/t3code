#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation

public enum BackendPortAllocatorError: Error, Equatable {
  case socketCreationFailed
  case invalidLoopbackAddress
  case bindFailed(Int32)
  case lookupFailed(Int32)
}

public enum BackendPortAllocator {
  public static func reserveLoopbackPort(host: String = "127.0.0.1") throws -> Int {
    let socketDescriptor = socket(AF_INET, numericSocketType(), 0)
    guard socketDescriptor >= 0 else {
      throw BackendPortAllocatorError.socketCreationFailed
    }
    defer {
      closeSocket(socketDescriptor)
    }

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(0).bigEndian

    let conversionResult = host.withCString { pointer in
      inet_pton(AF_INET, pointer, &address.sin_addr)
    }
    guard conversionResult == 1 else {
      throw BackendPortAllocatorError.invalidLoopbackAddress
    }

    var bindAddress = address
    let bindResult = withUnsafePointer(to: &bindAddress) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        bind(socketDescriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.stride))
      }
    }
    guard bindResult == 0 else {
      throw BackendPortAllocatorError.bindFailed(errno)
    }

    var resolvedAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
    let lookupResult = withUnsafeMutablePointer(to: &resolvedAddress) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        getsockname(socketDescriptor, sockaddrPointer, &length)
      }
    }
    guard lookupResult == 0 else {
      throw BackendPortAllocatorError.lookupFailed(errno)
    }

    return Int(UInt16(bigEndian: resolvedAddress.sin_port))
  }

  private static func numericSocketType() -> Int32 {
#if canImport(Darwin)
    return SOCK_STREAM
#else
    return Int32(SOCK_STREAM.rawValue)
#endif
  }

  private static func closeSocket(_ descriptor: Int32) {
#if canImport(Darwin)
    _ = Darwin.close(descriptor)
#else
    _ = Glibc.close(descriptor)
#endif
  }
}
