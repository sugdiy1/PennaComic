import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../l10n/l10n.dart';

// Windows 自带的"数据保护"(DPAPI):用当前登录用户的身份加密。
// 加密后的内容只有这台电脑上的这个用户能解开,文件被拷走或被网盘同步也读不出来。

final class _Blob extends Struct {
  @Uint32()
  external int size;
  external Pointer<Uint8> data;
}

typedef _CryptC = Int32 Function(
  Pointer<_Blob> input,
  Pointer<Void> description,
  Pointer<Void> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_Blob> output,
);
typedef _CryptDart = int Function(
  Pointer<_Blob> input,
  Pointer<Void> description,
  Pointer<Void> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_Blob> output,
);

// CRYPTPROTECT_UI_FORBIDDEN:任何情况下都不弹系统对话框。
const _noUi = 0x1;

final _crypt32 = DynamicLibrary.open('crypt32.dll');
final _protect = _crypt32.lookupFunction<_CryptC, _CryptDart>(
  'CryptProtectData',
);
final _unprotect = _crypt32.lookupFunction<_CryptC, _CryptDart>(
  'CryptUnprotectData',
);
final _localFree = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('LocalFree');

Uint8List dpapiProtect(Uint8List plain) => _run(_protect, plain);

/// 解不开(不是这台电脑这个用户加密的,或内容损坏)时抛 [StateError]。
Uint8List dpapiUnprotect(Uint8List cipher) => _run(_unprotect, cipher);

Uint8List _run(_CryptDart crypt, Uint8List input) {
  final inBlob = calloc<_Blob>();
  final outBlob = calloc<_Blob>();
  // 长度为 0 时也分配 1 字节,避免传空指针。
  final buffer = calloc<Uint8>(input.isEmpty ? 1 : input.length);
  try {
    buffer.asTypedList(input.length).setAll(0, input);
    inBlob.ref
      ..size = input.length
      ..data = buffer;
    final ok = crypt(
      inBlob,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      _noUi,
      outBlob,
    );
    if (ok == 0) throw StateError(tr('Windows 数据保护调用失败'));
    final out = Uint8List.fromList(
      outBlob.ref.data.asTypedList(outBlob.ref.size),
    );
    _localFree(outBlob.ref.data.cast());
    return out;
  } finally {
    calloc.free(buffer);
    calloc.free(inBlob);
    calloc.free(outBlob);
  }
}
