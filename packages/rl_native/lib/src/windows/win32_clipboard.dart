import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:rl_core/rl_core.dart';

import '../input_backend.dart';
import 'win32_ffi.dart';

typedef _ReleaseNative = Uint32 Function(Pointer<Void> thisPtr);
typedef _ReleaseDart = int Function(Pointer<Void> thisPtr);

int _comRelease(Pointer<Pointer<IntPtr>> pUnk) {
  if (pUnk == nullptr || pUnk.value == nullptr) return 0;
  final vtable = pUnk.value;
  final func = Pointer<NativeFunction<_ReleaseNative>>.fromAddress(vtable[2])
      .asFunction<_ReleaseDart>();
  return func(pUnk.cast<Void>());
}

void _setGuid(Pointer<GUID> guid, int d1, int d2, int d3, List<int> d4) {
  guid.ref.Data1 = d1;
  guid.ref.Data2 = d2;
  guid.ref.Data3 = d3;
  for (var i = 0; i < 8; i++) {
    guid.ref.Data4[i] = d4[i];
  }
}

// WIC COM vtable signatures
typedef _CreateDecoderFromStreamNative = Int32 Function(
    Pointer<Void> thisPtr,
    Pointer<Void> pIStream,
    Pointer<GUID> pguidVendor,
    Uint32 metadataOptions,
    Pointer<Pointer<Pointer<IntPtr>>> ppIDecoder);
typedef _CreateDecoderFromStreamDart = int Function(
    Pointer<Void> thisPtr,
    Pointer<Void> pIStream,
    Pointer<GUID> pguidVendor,
    int metadataOptions,
    Pointer<Pointer<Pointer<IntPtr>>> ppIDecoder);

typedef _CreateEncoderNative = Int32 Function(
    Pointer<Void> thisPtr,
    Pointer<GUID> guidContainerFormat,
    Pointer<GUID> pguidVendor,
    Pointer<Pointer<Pointer<IntPtr>>> ppIEncoder);
typedef _CreateEncoderDart = int Function(
    Pointer<Void> thisPtr,
    Pointer<GUID> guidContainerFormat,
    Pointer<GUID> pguidVendor,
    Pointer<Pointer<Pointer<IntPtr>>> ppIEncoder);

typedef _CreateFormatConverterNative = Int32 Function(
    Pointer<Void> thisPtr, Pointer<Pointer<Pointer<IntPtr>>> ppIFormatConverter);
typedef _CreateFormatConverterDart = int Function(
    Pointer<Void> thisPtr, Pointer<Pointer<Pointer<IntPtr>>> ppIFormatConverter);

typedef _CreateWicStreamNative = Int32 Function(
    Pointer<Void> thisPtr, Pointer<Pointer<Pointer<IntPtr>>> ppIWICStream);
typedef _CreateWicStreamDart = int Function(
    Pointer<Void> thisPtr, Pointer<Pointer<Pointer<IntPtr>>> ppIWICStream);

typedef _CreateBitmapFromMemoryNative = Int32 Function(
    Pointer<Void> thisPtr,
    Uint32 uiWidth,
    Uint32 uiHeight,
    Pointer<GUID> pixelFormat,
    Uint32 cbStride,
    Uint32 cbBufferSize,
    Pointer<Uint8> pbBuffer,
    Pointer<Pointer<Pointer<IntPtr>>> ppIBitmap);
typedef _CreateBitmapFromMemoryDart = int Function(
    Pointer<Void> thisPtr,
    int uiWidth,
    int uiHeight,
    Pointer<GUID> pixelFormat,
    int cbStride,
    int cbBufferSize,
    Pointer<Uint8> pbBuffer,
    Pointer<Pointer<Pointer<IntPtr>>> ppIBitmap);

typedef _InitFromIStreamNative = Int32 Function(
    Pointer<Void> thisPtr, Pointer<Void> pIStream);
typedef _InitFromIStreamDart = int Function(
    Pointer<Void> thisPtr, Pointer<Void> pIStream);

typedef _InitFromMemoryNative = Int32 Function(
    Pointer<Void> thisPtr, Pointer<Uint8> pbBuffer, Uint32 cbBufferSize);
typedef _InitFromMemoryDart = int Function(
    Pointer<Void> thisPtr, Pointer<Uint8> pbBuffer, int cbBufferSize);

typedef _GetFrameNative = Int32 Function(Pointer<Void> thisPtr, Uint32 index,
    Pointer<Pointer<Pointer<IntPtr>>> ppIBitmapFrame);
typedef _GetFrameDart = int Function(Pointer<Void> thisPtr, int index,
    Pointer<Pointer<Pointer<IntPtr>>> ppIBitmapFrame);

typedef _GetSizeNative = Int32 Function(Pointer<Void> thisPtr,
    Pointer<Uint32> puiWidth, Pointer<Uint32> puiHeight);
typedef _GetSizeDart = int Function(
    Pointer<Void> thisPtr, Pointer<Uint32> puiWidth, Pointer<Uint32> puiHeight);

typedef _CopyPixelsNative = Int32 Function(Pointer<Void> thisPtr,
    Pointer<Void> prc, Uint32 cbStride, Uint32 cbBufferSize, Pointer<Uint8> pbBuffer);
typedef _CopyPixelsDart = int Function(Pointer<Void> thisPtr,
    Pointer<Void> prc, int cbStride, int cbBufferSize, Pointer<Uint8> pbBuffer);

typedef _InitConverterNative = Int32 Function(
    Pointer<Void> thisPtr,
    Pointer<Void> pISource,
    Pointer<GUID> dstFormat,
    Uint32 dither,
    Pointer<Void> pIPalette,
    Double alphaThresholdPercent,
    Uint32 paletteTranslate);
typedef _InitConverterDart = int Function(
    Pointer<Void> thisPtr,
    Pointer<Void> pISource,
    Pointer<GUID> dstFormat,
    int dither,
    Pointer<Void> pIPalette,
    double alphaThresholdPercent,
    int paletteTranslate);

typedef _InitEncoderNative = Int32 Function(
    Pointer<Void> thisPtr, Pointer<Void> pIStream, Uint32 cacheOption);
typedef _InitEncoderDart = int Function(
    Pointer<Void> thisPtr, Pointer<Void> pIStream, int cacheOption);

typedef _CreateNewFrameNative = Int32 Function(
    Pointer<Void> thisPtr,
    Pointer<Pointer<Pointer<IntPtr>>> ppIFrameEncode,
    Pointer<Pointer<Void>> ppIEncoderOptions);
typedef _CreateNewFrameDart = int Function(
    Pointer<Void> thisPtr,
    Pointer<Pointer<Pointer<IntPtr>>> ppIFrameEncode,
    Pointer<Pointer<Void>> ppIEncoderOptions);

typedef _CommitNative = Int32 Function(Pointer<Void> thisPtr);
typedef _CommitDart = int Function(Pointer<Void> thisPtr);

typedef _InitFrameEncodeNative = Int32 Function(
    Pointer<Void> thisPtr, Pointer<Void> pIEncoderOptions);
typedef _InitFrameEncodeDart = int Function(
    Pointer<Void> thisPtr, Pointer<Void> pIEncoderOptions);

typedef _SetSizeNative = Int32 Function(
    Pointer<Void> thisPtr, Uint32 uiWidth, Uint32 uiHeight);
typedef _SetSizeDart = int Function(
    Pointer<Void> thisPtr, int uiWidth, int uiHeight);

typedef _WriteSourceNative = Int32 Function(
    Pointer<Void> thisPtr, Pointer<Void> pIBitmapSource, Pointer<Void> prc);
typedef _WriteSourceDart = int Function(
    Pointer<Void> thisPtr, Pointer<Void> pIBitmapSource, Pointer<Void> prc);

typedef _FrameCommitNative = Int32 Function(Pointer<Void> thisPtr);
typedef _FrameCommitDart = int Function(Pointer<Void> thisPtr);

/// Windows clipboard access.
///
/// ## Why polling beats notification here
///
/// Windows offers `AddClipboardFormatListener`, which posts
/// `WM_CLIPBOARDUPDATE` to a window. Using it would require creating a hidden
/// window and pumping a message loop on a dedicated thread — real complexity,
/// and awkward to reach from Dart at all.
///
/// `GetClipboardSequenceNumber` is the alternative: a single system call that
/// returns a counter incremented on every clipboard change. Reading it costs
/// well under a microsecond, so polling at 50 ms is roughly 20 calls a second
/// and immeasurable CPU — while comfortably meeting the sub-100 ms sync target.
/// The clipboard itself is only opened when the counter actually moved.
///
/// ## Opening the clipboard is a shared, contended resource
///
/// Only one process may hold the clipboard open at a time, and a badly written
/// application can hold it for hundreds of milliseconds. Every open here is
/// therefore retried briefly and released in a `finally` — leaking the handle
/// would wedge copy-and-paste system-wide until RemoteLink exited, which is
/// about the most user-hostile bug this component could have.
final class Win32ClipboardBackend implements ClipboardBackend {
  Win32ClipboardBackend() : _bindings = Win32Bindings() {
    final name = kExcludeFromMonitoring.toNativeUtf16();
    try {
      _excludeFormat = _bindings.registerClipboardFormat(name);
    } finally {
      calloc.free(name);
    }
  }

  static const int _openAttempts = 5;
  static const Duration _openRetryDelay = Duration(milliseconds: 2);

  final Win32Bindings _bindings;
  final Log _log = Log.scoped('native.clipboard.win32');

  late final int _excludeFormat;
  bool _disposed = false;

  @override
  bool get isAvailable => !_disposed;

  @override
  int get changeCount => _bindings.getClipboardSequenceNumber();

  @override
  bool get isConcealed =>
      _excludeFormat != 0 &&
      _bindings.isClipboardFormatAvailable(_excludeFormat) != 0;

  /// Runs [body] with the clipboard open, retrying briefly if another process
  /// holds it.
  T? _withClipboard<T>(T? Function() body) {
    for (var attempt = 0; attempt < _openAttempts; attempt++) {
      if (_bindings.openClipboard(0) != 0) {
        try {
          return body();
        } finally {
          _bindings.closeClipboard();
        }
      }
      // A busy-wait rather than an async delay: this whole API is synchronous
      // by design, and the contention window is single-digit milliseconds.
      final deadline = DateTime.now().add(_openRetryDelay);
      while (DateTime.now().isBefore(deadline)) {
        // Spin.
      }
    }
    _log.debug(() => 'clipboard busy after $_openAttempts attempts');
    return null;
  }

  @override
  String? readText() {
    if (_disposed) return null;
    if (_bindings.isClipboardFormatAvailable(CF_UNICODETEXT) == 0) return null;

    return _withClipboard<String?>(() {
      final handle = _bindings.getClipboardData(CF_UNICODETEXT);
      if (handle == 0) return null;

      final pointer = _bindings.globalLock(handle);
      if (pointer == nullptr) return null;
      try {
        return pointer.cast<Utf16>().toDartString();
      } finally {
        _bindings.globalUnlock(handle);
      }
    });
  }

  @override
  void writeText(String text) {
    if (_disposed) return;

    // UTF-16 plus a null terminator, which CF_UNICODETEXT requires.
    final units = text.codeUnits;
    final byteLength = (units.length + 1) * 2;

    final handle = _bindings.globalAlloc(GMEM_MOVEABLE, byteLength);
    if (handle == 0) {
      _log.warn('GlobalAlloc failed for a clipboard write');
      return;
    }

    final pointer = _bindings.globalLock(handle);
    if (pointer == nullptr) {
      _bindings.globalFree(handle);
      return;
    }

    final buffer = pointer.cast<Uint16>();
    for (var i = 0; i < units.length; i++) {
      buffer[i] = units[i];
    }
    buffer[units.length] = 0;
    _bindings.globalUnlock(handle);

    final placed = _withClipboard<bool>(() {
          _bindings.emptyClipboard();
          // On success the clipboard *takes ownership* of the handle, so it
          // must not be freed. On failure ownership stays here and it must be.
          // Getting this backwards is either a leak or a double free.
          return _bindings.setClipboardData(CF_UNICODETEXT, handle) != 0;
        }) ??
        false;

    if (!placed) _bindings.globalFree(handle);
  }

  @override
  List<int>? readImagePng() {
    if (_disposed) return null;

    // Prefer CF_DIBV5 over CF_DIB because CF_DIB lacks alpha channel information.
    final format = _bindings.isClipboardFormatAvailable(CF_DIBV5) != 0
        ? CF_DIBV5
        : (_bindings.isClipboardFormatAvailable(CF_DIB) != 0 ? CF_DIB : 0);
    if (format == 0) return null;

    return _withClipboard<List<int>?>(() {
      final handle = _bindings.getClipboardData(format);
      if (handle == 0) return null;

      final pointer = _bindings.globalLock(handle);
      if (pointer == nullptr) return null;
      try {
        return _dibToPng(pointer, format);
      } finally {
        _bindings.globalUnlock(handle);
      }
    });
  }

  List<int>? _dibToPng(Pointer<Void> pointer, int format) {
    final headerSize = pointer.cast<Uint32>().value;
    final width = pointer.cast<Int32>()[1];
    final height = pointer.cast<Int32>()[2];
    final bitCount = pointer.cast<Uint16>()[7];
    final compression = pointer.cast<Uint32>()[4];
    if (width <= 0 || height == 0) return null;

    final isBottomUp = height > 0;
    final absHeight = height.abs();

    int offset;
    int stride;
    final guidFormat = calloc<GUID>();

    try {
      if (format == CF_DIBV5) {
        // GUID_WICPixelFormat32bppBGRA
        _setGuid(guidFormat, 0x6fddc324, 0x4e03, 0x4b15,
            const <int>[0x83, 0x2c, 0x5a, 0xe5, 0x0d, 0x93, 0x4b, 0x9d]);
        stride = width * 4;
        offset = headerSize >= 124 ? headerSize : 124;
      } else {
        if (bitCount == 32) {
          // GUID_WICPixelFormat32bppBGR
          _setGuid(guidFormat, 0x6fddc324, 0x4e03, 0x4b15,
              const <int>[0x83, 0x2c, 0x5a, 0xe5, 0x0d, 0x93, 0x4b, 0xba]);
          stride = width * 4;
          offset = (headerSize == 40 && compression == BI_BITFIELDS)
              ? 52
              : headerSize;
        } else if (bitCount == 24) {
          // GUID_WICPixelFormat24bppBGR
          _setGuid(guidFormat, 0x6fddc324, 0x4e03, 0x4b15,
              const <int>[0x83, 0x2c, 0x5a, 0xe5, 0x0d, 0x93, 0x4b, 0x8e]);
          stride = ((width * 3 + 3) ~/ 4) * 4;
          offset = headerSize;
        } else {
          return null;
        }
      }

      final bufferSize = stride * absHeight;
      final topDownBuffer = calloc<Uint8>(bufferSize);
      try {
        final srcPixels = pointer.cast<Uint8>().elementAt(offset);
        if (isBottomUp) {
          for (var y = 0; y < absHeight; y++) {
            final srcRow = srcPixels.elementAt((absHeight - 1 - y) * stride);
            final dstRow = topDownBuffer.elementAt(y * stride);
            dstRow.asTypedList(stride).setAll(0, srcRow.asTypedList(stride));
          }
        } else {
          topDownBuffer.asTypedList(bufferSize).setAll(
                0,
                srcPixels.asTypedList(bufferSize),
              );
        }

        return _encodePixelsToPng(
          width,
          absHeight,
          guidFormat,
          stride,
          bufferSize,
          topDownBuffer,
        );
      } finally {
        calloc.free(topDownBuffer);
      }
    } finally {
      calloc.free(guidFormat);
    }
  }

  List<int>? _encodePixelsToPng(
    int width,
    int height,
    Pointer<GUID> pixelFormatGuid,
    int stride,
    int bufferSize,
    Pointer<Uint8> pbBuffer,
  ) {
    _bindings.coInitializeEx(nullptr, COINIT_MULTITHREADED);

    final clsidFactory = calloc<GUID>();
    final iidFactory = calloc<GUID>();
    final ppFactory = calloc<Pointer<Pointer<IntPtr>>>();

    try {
      _setGuid(clsidFactory, 0xcacaf262, 0x5153, 0x4c8e,
          const <int>[0xae, 0x85, 0x60, 0xf0, 0xa3, 0x6b, 0x9f, 0x23]);
      _setGuid(iidFactory, 0xec5ec8a9, 0xc395, 0x4314,
          const <int>[0x9c, 0x77, 0x54, 0xd7, 0xa9, 0x35, 0xff, 0x70]);

      if (_bindings.coCreateInstance(
            clsidFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            iidFactory,
            ppFactory.cast(),
          ) !=
          0) {
        return null;
      }

      final pFactory = ppFactory.value;
      try {
        // CreateBitmapFromMemory (vtable index 20 on IWICImagingFactory)
        final ppBitmap = calloc<Pointer<Pointer<IntPtr>>>();
        final createBitmapFromMem =
            Pointer<NativeFunction<_CreateBitmapFromMemoryNative>>.fromAddress(
                    pFactory.value[20])
                .asFunction<_CreateBitmapFromMemoryDart>();

        if (createBitmapFromMem(
              pFactory.cast(),
              width,
              height,
              pixelFormatGuid,
              stride,
              bufferSize,
              pbBuffer,
              ppBitmap,
            ) !=
            0) {
          calloc.free(ppBitmap);
          return null;
        }
        final pBitmap = ppBitmap.value;
        calloc.free(ppBitmap);

        try {
          // CreateStreamOnHGlobal
          final ppIStream = calloc<Pointer<Void>>();
          if (_bindings.createStreamOnHGlobal(0, 1, ppIStream) != 0) {
            calloc.free(ppIStream);
            return null;
          }
          final pIStream = ppIStream.value.cast<Pointer<IntPtr>>();
          calloc.free(ppIStream);

          try {
            // CreateStream (vtable index 14 on IWICImagingFactory)
            final ppWicStream = calloc<Pointer<Pointer<IntPtr>>>();
            final createWicStream =
                Pointer<NativeFunction<_CreateWicStreamNative>>.fromAddress(
                        pFactory.value[14])
                    .asFunction<_CreateWicStreamDart>();
            if (createWicStream(pFactory.cast(), ppWicStream) != 0) {
              calloc.free(ppWicStream);
              return null;
            }
            final pWicStream = ppWicStream.value;
            calloc.free(ppWicStream);

            try {
              // InitializeFromIStream (vtable index 14 on IWICStream)
              final initFromIStream =
                  Pointer<NativeFunction<_InitFromIStreamNative>>.fromAddress(
                          pWicStream.value[14])
                      .asFunction<_InitFromIStreamDart>();
              if (initFromIStream(pWicStream.cast(), pIStream.cast()) != 0) {
                return null;
              }

              // CreateEncoder (vtable index 8 on IWICImagingFactory)
              final guidPng = calloc<GUID>();
              _setGuid(guidPng, 0x1b7cfdf4, 0x714f, 0x4c8b,
                  const <int>[0x88, 0x33, 0x28, 0x95, 0xcd, 0xae, 0x63, 0x4e]);
              final ppEncoder = calloc<Pointer<Pointer<IntPtr>>>();
              final createEncoder =
                  Pointer<NativeFunction<_CreateEncoderNative>>.fromAddress(
                          pFactory.value[8])
                      .asFunction<_CreateEncoderDart>();
              final hrEnc = createEncoder(
                pFactory.cast(),
                guidPng,
                nullptr,
                ppEncoder,
              );
              calloc.free(guidPng);
              if (hrEnc != 0) {
                calloc.free(ppEncoder);
                return null;
              }
              final pEncoder = ppEncoder.value;
              calloc.free(ppEncoder);

              try {
                // Initialize encoder (vtable index 3 on IWICBitmapEncoder)
                final initEncoder =
                    Pointer<NativeFunction<_InitEncoderNative>>.fromAddress(
                            pEncoder.value[3])
                        .asFunction<_InitEncoderDart>();
                if (initEncoder(
                      pEncoder.cast(),
                      pWicStream.cast(),
                      WICBitmapEncoderNoCache,
                    ) !=
                    0) {
                  return null;
                }

                // CreateNewFrame (vtable index 10 on IWICBitmapEncoder)
                final ppFrame = calloc<Pointer<Pointer<IntPtr>>>();
                final createNewFrame =
                    Pointer<NativeFunction<_CreateNewFrameNative>>.fromAddress(
                            pEncoder.value[10])
                        .asFunction<_CreateNewFrameDart>();
                if (createNewFrame(pEncoder.cast(), ppFrame, nullptr) != 0) {
                  calloc.free(ppFrame);
                  return null;
                }
                final pFrame = ppFrame.value;
                calloc.free(ppFrame);

                try {
                  // Initialize frame (vtable index 3 on IWICBitmapFrameEncode)
                  final initFrame =
                      Pointer<NativeFunction<_InitFrameEncodeNative>>.fromAddress(
                              pFrame.value[3])
                          .asFunction<_InitFrameEncodeDart>();
                  if (initFrame(pFrame.cast(), nullptr) != 0) return null;

                  // SetSize (vtable index 4 on IWICBitmapFrameEncode)
                  final setSize =
                      Pointer<NativeFunction<_SetSizeNative>>.fromAddress(
                              pFrame.value[4])
                          .asFunction<_SetSizeDart>();
                  if (setSize(pFrame.cast(), width, height) != 0) return null;

                  // WriteSource (vtable index 11 on IWICBitmapFrameEncode)
                  final writeSource =
                      Pointer<NativeFunction<_WriteSourceNative>>.fromAddress(
                              pFrame.value[11])
                          .asFunction<_WriteSourceDart>();
                  if (writeSource(pFrame.cast(), pBitmap.cast(), nullptr) !=
                      0) {
                    return null;
                  }

                  // Commit frame (vtable index 12 on IWICBitmapFrameEncode)
                  final frameCommit =
                      Pointer<NativeFunction<_FrameCommitNative>>.fromAddress(
                              pFrame.value[12])
                          .asFunction<_FrameCommitDart>();
                  if (frameCommit(pFrame.cast()) != 0) return null;

                  // Commit encoder (vtable index 11 on IWICBitmapEncoder)
                  final encoderCommit =
                      Pointer<NativeFunction<_CommitNative>>.fromAddress(
                              pEncoder.value[11])
                          .asFunction<_CommitDart>();
                  if (encoderCommit(pEncoder.cast()) != 0) return null;

                  // Read bytes from IStream using GetHGlobalFromStream
                  final phGlobal = calloc<IntPtr>();
                  if (_bindings.getHGlobalFromStream(
                        pIStream.cast(),
                        phGlobal,
                      ) !=
                      0) {
                    calloc.free(phGlobal);
                    return null;
                  }
                  final hOutGlobal = phGlobal.value;
                  calloc.free(phGlobal);

                  final outPtr = _bindings.globalLock(hOutGlobal);
                  if (outPtr == nullptr) return null;
                  try {
                    final outSize = _bindings.globalSize(hOutGlobal);
                    return Uint8List.fromList(
                      outPtr.cast<Uint8>().asTypedList(outSize),
                    );
                  } finally {
                    _bindings.globalUnlock(hOutGlobal);
                  }
                } finally {
                  _comRelease(pFrame);
                }
              } finally {
                _comRelease(pEncoder);
              }
            } finally {
              _comRelease(pWicStream);
            }
          } finally {
            _comRelease(pIStream);
          }
        } finally {
          _comRelease(pBitmap);
        }
      } finally {
        _comRelease(pFactory);
      }
    } finally {
      calloc.free(clsidFactory);
      calloc.free(iidFactory);
      calloc.free(ppFactory);
    }
  }

  @override
  void writeImagePng(List<int> pngBytes) {
    if (_disposed) return;
    if (pngBytes.isEmpty) return;

    _bindings.coInitializeEx(nullptr, COINIT_MULTITHREADED);

    final clsidFactory = calloc<GUID>();
    final iidFactory = calloc<GUID>();
    final ppFactory = calloc<Pointer<Pointer<IntPtr>>>();

    try {
      _setGuid(clsidFactory, 0xcacaf262, 0x5153, 0x4c8e,
          const <int>[0xae, 0x85, 0x60, 0xf0, 0xa3, 0x6b, 0x9f, 0x23]);
      _setGuid(iidFactory, 0xec5ec8a9, 0xc395, 0x4314,
          const <int>[0x9c, 0x77, 0x54, 0xd7, 0xa9, 0x35, 0xff, 0x70]);

      if (_bindings.coCreateInstance(
            clsidFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            iidFactory,
            ppFactory.cast(),
          ) !=
          0) {
        return;
      }

      final pFactory = ppFactory.value;
      try {
        // CreateStream (vtable index 14 on IWICImagingFactory)
        final ppWicStream = calloc<Pointer<Pointer<IntPtr>>>();
        final createWicStream =
            Pointer<NativeFunction<_CreateWicStreamNative>>.fromAddress(
                    pFactory.value[14])
                .asFunction<_CreateWicStreamDart>();
        if (createWicStream(pFactory.cast(), ppWicStream) != 0) {
          calloc.free(ppWicStream);
          return;
        }
        final pWicStream = ppWicStream.value;
        calloc.free(ppWicStream);

        try {
          final nativePngBytes = calloc<Uint8>(pngBytes.length);
          nativePngBytes.asTypedList(pngBytes.length).setAll(0, pngBytes);

          try {
            // InitializeFromMemory (vtable index 16 on IWICStream)
            final initFromMem =
                Pointer<NativeFunction<_InitFromMemoryNative>>.fromAddress(
                        pWicStream.value[16])
                    .asFunction<_InitFromMemoryDart>();
            if (initFromMem(
                  pWicStream.cast(),
                  nativePngBytes,
                  pngBytes.length,
                ) !=
                0) {
              return;
            }

            // CreateDecoderFromStream (vtable index 4 on IWICImagingFactory)
            final ppDecoder = calloc<Pointer<Pointer<IntPtr>>>();
            final createDecoder =
                Pointer<NativeFunction<_CreateDecoderFromStreamNative>>.fromAddress(
                        pFactory.value[4])
                    .asFunction<_CreateDecoderFromStreamDart>();
            if (createDecoder(
                  pFactory.cast(),
                  pWicStream.cast(),
                  nullptr,
                  WICDecodeMetadataCacheOnDemand,
                  ppDecoder,
                ) !=
                0) {
              calloc.free(ppDecoder);
              return;
            }
            final pDecoder = ppDecoder.value;
            calloc.free(ppDecoder);

            try {
              // GetFrame 0 (vtable index 13 on IWICBitmapDecoder)
              final ppFrame = calloc<Pointer<Pointer<IntPtr>>>();
              final getFrame =
                  Pointer<NativeFunction<_GetFrameNative>>.fromAddress(
                          pDecoder.value[13])
                      .asFunction<_GetFrameDart>();
              if (getFrame(pDecoder.cast(), 0, ppFrame) != 0) {
                calloc.free(ppFrame);
                return;
              }
              final pFrame = ppFrame.value;
              calloc.free(ppFrame);

              try {
                // CreateFormatConverter (vtable index 10 on IWICImagingFactory)
                final ppConverter = calloc<Pointer<Pointer<IntPtr>>>();
                final createConverter =
                    Pointer<NativeFunction<_CreateFormatConverterNative>>.fromAddress(
                            pFactory.value[10])
                        .asFunction<_CreateFormatConverterDart>();
                if (createConverter(pFactory.cast(), ppConverter) != 0) {
                  calloc.free(ppConverter);
                  return;
                }
                final pConverter = ppConverter.value;
                calloc.free(ppConverter);

                try {
                  final guidBgra = calloc<GUID>();
                  _setGuid(guidBgra, 0x6fddc324, 0x4e03, 0x4b15,
                      const <int>[0x83, 0x2c, 0x5a, 0xe5, 0x0d, 0x93, 0x4b, 0x9d]);

                  // Initialize converter (vtable index 8 on IWICFormatConverter)
                  final initConv =
                      Pointer<NativeFunction<_InitConverterNative>>.fromAddress(
                              pConverter.value[8])
                          .asFunction<_InitConverterDart>();
                  final hrConv = initConv(
                    pConverter.cast(),
                    pFrame.cast(),
                    guidBgra,
                    0, // WICBitmapDitherTypeNone
                    nullptr,
                    0.0,
                    0, // WICBitmapPaletteTypeCustom
                  );
                  calloc.free(guidBgra);
                  if (hrConv != 0) return;

                  // GetSize (vtable index 3 on IWICBitmapSource)
                  final pWidth = calloc<Uint32>();
                  final pHeight = calloc<Uint32>();
                  final getSize =
                      Pointer<NativeFunction<_GetSizeNative>>.fromAddress(
                              pConverter.value[3])
                          .asFunction<_GetSizeDart>();
                  if (getSize(pConverter.cast(), pWidth, pHeight) != 0) {
                    calloc.free(pWidth);
                    calloc.free(pHeight);
                    return;
                  }
                  final width = pWidth.value;
                  final height = pHeight.value;
                  calloc.free(pWidth);
                  calloc.free(pHeight);

                  if (width <= 0 || height <= 0) return;

                  final stride = width * 4;
                  final bufferSize = stride * height;
                  final tempPixels = calloc<Uint8>(bufferSize);

                  try {
                    // CopyPixels (vtable index 7 on IWICBitmapSource)
                    final copyPixels =
                        Pointer<NativeFunction<_CopyPixelsNative>>.fromAddress(
                                pConverter.value[7])
                            .asFunction<_CopyPixelsDart>();
                    if (copyPixels(
                          pConverter.cast(),
                          nullptr,
                          stride,
                          bufferSize,
                          tempPixels,
                        ) !=
                        0) {
                      return;
                    }

                    // Allocate CF_DIBV5 global memory (124 byte header + pixels)
                    final totalBytes = 124 + bufferSize;
                    final handle =
                        _bindings.globalAlloc(GMEM_MOVEABLE, totalBytes);
                    if (handle == 0) {
                      _log.warn('GlobalAlloc failed for clipboard image write');
                      return;
                    }

                    final pointer = _bindings.globalLock(handle);
                    if (pointer == nullptr) {
                      _bindings.globalFree(handle);
                      return;
                    }

                    final pBytes = pointer.cast<Uint8>();
                    for (var i = 0; i < 124; i++) {
                      pBytes[i] = 0;
                    }

                    final p32 = pointer.cast<Uint32>();
                    final p32Signed = pointer.cast<Int32>();
                    final p16 = pointer.cast<Uint16>();

                    p32[0] = 124; // bV5Size
                    p32Signed[1] = width; // bV5Width
                    p32Signed[2] = height; // bV5Height (bottom-up)
                    p16[6] = 1; // bV5Planes
                    p16[7] = 32; // bV5BitCount
                    p32[4] = BI_BITFIELDS; // bV5Compression
                    p32[5] = bufferSize; // bV5SizeImage
                    p32[10] = 0x00FF0000; // bV5RedMask
                    p32[11] = 0x0000FF00; // bV5GreenMask
                    p32[12] = 0x000000FF; // bV5BlueMask
                    p32[13] = 0xFF000000; // bV5AlphaMask
                    p32[14] = LCS_sRGB; // bV5CSType
                    p32[27] = LCS_GM_IMAGES; // bV5Intent

                    // Flip scanlines to bottom-up DIB order
                    final destPixels = pointer.cast<Uint8>().elementAt(124);
                    for (var y = 0; y < height; y++) {
                      final srcRow = tempPixels.elementAt(y * stride);
                      final dstRow =
                          destPixels.elementAt((height - 1 - y) * stride);
                      dstRow
                          .asTypedList(stride)
                          .setAll(0, srcRow.asTypedList(stride));
                    }

                    _bindings.globalUnlock(handle);

                    final placed = _withClipboard<bool>(() {
                          _bindings.emptyClipboard();
                          return _bindings.setClipboardData(
                                CF_DIBV5,
                                handle,
                              ) !=
                              0;
                        }) ??
                        false;

                    if (!placed) _bindings.globalFree(handle);
                  } finally {
                    calloc.free(tempPixels);
                  }
                } finally {
                  _comRelease(pConverter);
                }
              } finally {
                _comRelease(pFrame);
              }
            } finally {
              _comRelease(pDecoder);
            }
          } finally {
            calloc.free(nativePngBytes);
          }
        } finally {
          _comRelease(pWicStream);
        }
      } finally {
        _comRelease(pFactory);
      }
    } finally {
      calloc.free(clsidFactory);
      calloc.free(iidFactory);
      calloc.free(ppFactory);
    }
  }

  @override
  void dispose() => _disposed = true;
}

