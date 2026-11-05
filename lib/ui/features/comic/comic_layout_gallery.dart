import 'package:flutter/material.dart';

import '../../../core/harness/comic/comic_layout_catalog.dart';
import 'comic_preview.dart';

Future<void> showComicLayoutGallery(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _Gallery());

class _Gallery extends StatefulWidget {
  const _Gallery();
  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = comicLayouts
        .where(
          (l) => '${l.id} ${l.name} ${l.purpose} ${l.tags.join(' ')}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    return Dialog(
      child: SizedBox(
        width: 980,
        height: 720,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '121套漫画布局 · AI按故事自动匹配',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Text('15类构图的比例与重心变体，加一套整页。右到左阅读；变体不是独立的叙事理论。'),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: '搜索编号、对白、动作、悬念、静场…',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: c.maxWidth < 600 ? 2 : 4,
                      mainAxisExtent: 230,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final l = filtered[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Center(
                                  child: AspectRatio(
                                    aspectRatio: 2 / 3,
                                    child: CustomPaint(
                                      painter: _TemplatePainter(l),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${l.id} · ${l.name}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${l.panels.length}格 · ${l.tags.join('/')}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              Text(
                                l.purpose,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplatePainter extends CustomPainter {
  _TemplatePainter(this.template);
  final ComicLayoutTemplate template;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final panels = template.pixelPanels(1000, 1500);
    canvas.scale(size.width / 1000, size.height / 1500);
    for (final (i, panel) in panels.indexed) {
      final path = comicPanelPath({...panel, 'bbox': panel['box']});
      canvas.drawPath(path, Paint()..color = const Color(0xffe8eef8));
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xff425878)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12,
      );
      final b = path.getBounds();
      final text = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(fontSize: 80, color: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, b.center - Offset(text.width / 2, text.height / 2));
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _TemplatePainter old) =>
      old.template.id != template.id;
}
