import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  group('压缩大图', () {
    test('大图缩到 2048 以内并转成 WebP;小图原样', () async {
      // 噪点图压不小,PNG 能有好几 MB,像一张大截图。
      final random = Random(1);
      final noise = img.Image(width: 3000, height: 1500);
      for (final p in noise) {
        p.setRgb(random.nextInt(256), random.nextInt(256), random.nextInt(256));
      }
      final png = img.encodePng(noise);
      expect(png.length, greaterThan(compressAboveBytes));

      final out = await compressImage(
        Attachment.image(name: 'shot.png', mime: 'image/png', bytes: png),
      );

      expect(out.compressed, isTrue);
      expect(out.mime, 'image/webp');
      expect(out.name, 'shot.webp');
      expect(out.bytes!.length, lessThan(png.length));
      final back = img.decodeWebP(out.bytes!)!;
      expect([back.width, back.height], [2048, 1024]);

      final small = Attachment.image(
        name: 'a.png',
        mime: 'image/png',
        bytes: img.encodePng(img.Image(width: 8, height: 8)),
      );
      expect(identical(await compressImage(small), small), isTrue);
    });

    test('剪贴板贴进来的 BMP:比 10 MB 大也能压成 WebP;不压缩时转成真正的 PNG', () async {
      // Windows 上 pasteboard 给的就是不压缩的 32 位 BMP。
      final bmp = img.encodeBmp(
        img.Image(width: 3000, height: 1500, numChannels: 4),
      );
      expect(bmp.length, greaterThan(maxImageBytes));

      final webp = (await pastedImage(bmp, compress: true))!;
      expect((webp.mime, webp.compressed), ('image/webp', true));
      expect(webp.name, endsWith('.webp'));
      expect(webp.bytes!.length, lessThan(maxImageBytes));
      final back = img.decodeWebP(webp.bytes!)!;
      expect([back.width, back.height], [2048, 1024]);

      final png = (await pastedImage(bmp, compress: false))!;
      expect((png.mime, png.compressed), ('image/png', false));
      expect(img.decodePng(png.bytes!)!.width, 3000);

      expect(await pastedImage(Uint8List(10), compress: true), isNull);
    });
  });

  group('自动审批', () {
    StudioViewModel studio({required bool auto}) {
      final config = tempConfig();
      config.update(const AppConfig().copyWith(autoApprove: auto));
      return StudioViewModel(
        config: config,
        streamChat: (_) => const Stream.empty(),
        blocks: const [(text: 'a fox', pinned: false)],
      );
    }

    test('关着时等确认,开着时直接采纳', () {
      final manual = studio(auto: false)..proposeDraft('a red fox');
      expect(manual.pending, isNotNull);
      expect(manual.body, 'a fox');

      final auto = studio(auto: true)..proposeDraft('a red fox');
      expect(auto.pending, isNull);
      expect(auto.body, 'a red fox');
    });
  });
}
