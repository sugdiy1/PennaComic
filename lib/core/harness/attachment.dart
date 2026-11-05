import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../l10n/l10n.dart';

/// 一条消息最多带几个附件。
const maxAttachments = 6;

/// 单张图片的大小上限(字节)。图片会整张编码进请求,太大接口会拒收。
const maxImageBytes = 10 * 1024 * 1024;

/// 给用户看的图片大小上限。
const maxImageLabel = '10 MB';

/// 开着压缩时能读进来的原图上限:压缩完再按 [maxImageBytes] 查。
const maxRawImageBytes = 40 * 1024 * 1024;
const maxRawImageLabel = '40 MB';

/// 比这个大的图片(开着压缩时)缩小并转成 WebP 再发。
const compressAboveBytes = 1024 * 1024;

/// 压缩后长边最多多少像素;模型看图时多半也会缩到这么大。
const compressMaxSide = 2048;

/// 单个文本附件的长度上限(字符数),和 Skill 正文的上限一致。
const maxFileChars = 60000;

/// 认得的图片扩展名和对应的类型。
const imageMimes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/gif',
};

/// 随消息发给模型的附件:图片([bytes] + [mime])或文本文件([text])。
@immutable
class Attachment {
  const Attachment.image({
    required this.name,
    required String this.mime,
    required Uint8List this.bytes,
    this.compressed = false,
  }) : text = null;

  const Attachment.text({required this.name, required String this.text})
    : mime = null,
      bytes = null,
      compressed = false;

  final String name;
  final String? mime;
  final Uint8List? bytes;
  final String? text;

  /// 这张图是被 [compressImage] 缩小、转成 WebP 的。
  final bool compressed;

  bool get isImage => bytes != null;
}

/// 给用户看的附件错误。
class AttachmentException implements Exception {
  const AttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 大图缩小、转成有损 WebP。不够大、是动图、解不开、转完反而更大时原样返回。
Future<Attachment> compressImage(Attachment a) async {
  final bytes = a.bytes;
  if (bytes == null || bytes.length <= compressAboveBytes) return a;
  if (a.mime == 'image/gif') return a;
  // 解码和编码都很费时,放到另一个线程,窗口不卡。
  final out = await Isolate.run(() => _toWebP(bytes));
  if (out == null || out.length >= bytes.length) return a;
  final dot = a.name.lastIndexOf('.');
  return Attachment.image(
    name: '${dot < 0 ? a.name : a.name.substring(0, dot)}.webp',
    mime: 'image/webp',
    bytes: out,
    compressed: true,
  );
}

/// 档案库、角色库的预览图:长边缩到这么大。
const previewMaxSide = 768;

/// 把一张图转成预览用的 WebP(长边缩到 [previewMaxSide]),在另一个线程里做。
/// 读不了返回 null。
Future<Uint8List?> toPreviewWebP(Uint8List bytes) =>
    Isolate.run(() => _toWebP(bytes, maxSide: previewMaxSide));

Uint8List? _toWebP(Uint8List bytes, {int maxSide = compressMaxSide}) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  return _webP(_shrink(image, maxSide));
}

/// 长边超过 [maxSide] 时等比缩到 [maxSide]。
img.Image _shrink(img.Image image, int maxSide) {
  if (max(image.width, image.height) <= maxSide) return image;
  final wide = image.width >= image.height;
  return img.copyResize(
    image,
    width: wide ? maxSide : null,
    height: wide ? null : maxSide,
    interpolation: img.Interpolation.average,
  );
}

Uint8List _webP(img.Image image) =>
    img.encodeWebP(image, lossless: false, quality: 80, singleFrame: true);

/// 剪贴板里贴进来的图最大多少字节。Windows 上 `pasteboard` 给的是不压缩的 32 位 BMP
/// (宽 × 高 × 4),比原图大得多,所以这条线远高于图片文件的 [maxRawImageBytes]。
const maxPastedBytes = 512 * 1024 * 1024;

/// 把剪贴板里的图(Windows 上是不压缩的 BMP)转成能发给模型的附件:
/// [compress] 时缩到长边 [compressMaxSide] 的 WebP,否则原尺寸的 PNG。
/// 在另一个线程里做。读不了返回 null。
Future<Attachment?> pastedImage(Uint8List raw, {required bool compress}) async {
  final out = await Isolate.run(() {
    final image = img.decodeImage(raw);
    if (image == null) return null;
    return compress
        ? _webP(_shrink(image, compressMaxSide))
        : img.encodePng(image);
  });
  if (out == null) return null;
  final name = tr('粘贴的图片.png');
  return Attachment.image(
    name: compress ? name.replaceFirst(RegExp(r'\.png$'), '.webp') : name,
    mime: compress ? 'image/webp' : 'image/png',
    bytes: out,
    // 本来就小的截图转一下格式不算"压缩了大图",不提示。
    compressed: compress && raw.length > compressAboveBytes,
  );
}

/// 把一个文件读成附件:图片按扩展名认,其余的当 UTF-8 文本读。
/// [compress] 为真时大图先经 [compressImage] 缩小。
/// 太大、读不了、既不是图片也不是文本时抛 [AttachmentException]。
Future<Attachment> readAttachment(File file, {bool compress = false}) async {
  final name = file.uri.pathSegments.last;
  final dot = name.lastIndexOf('.');
  final mime = dot < 0
      ? null
      : imageMimes[name.substring(dot + 1).toLowerCase()];
  final Uint8List bytes;
  try {
    final size = await file.length();
    if (mime != null && size > (compress ? maxRawImageBytes : maxImageBytes)) {
      throw AttachmentException(
        tr('「{0}」超过 {1}', [name, compress ? maxRawImageLabel : maxImageLabel]),
      );
    }
    // UTF-8 一个字符最多 4 字节,超过这个数一定超长,不用读进来再数。
    if (mime == null && size > maxFileChars * 4) {
      throw AttachmentException(tr('「{0}」太长', [name]));
    }
    bytes = await file.readAsBytes();
  } on FileSystemException {
    throw AttachmentException(tr('读不了「{0}」', [name]));
  }
  if (mime != null) {
    final image = Attachment.image(name: name, mime: mime, bytes: bytes);
    final sent = compress ? await compressImage(image) : image;
    if (sent.bytes!.length > maxImageBytes) {
      throw AttachmentException(tr('「{0}」超过 {1}', [name, maxImageLabel]));
    }
    return sent;
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw AttachmentException(tr('「{0}」不是图片或文本', [name]));
  }
  // 二进制文件碰巧能按 UTF-8 解开时,里面通常有 NUL。
  if (text.contains('\u0000')) {
    throw AttachmentException(tr('「{0}」不是图片或文本', [name]));
  }
  if (text.length > maxFileChars) {
    throw AttachmentException(tr('「{0}」太长', [name]));
  }
  return Attachment.text(name: name, text: text);
}
