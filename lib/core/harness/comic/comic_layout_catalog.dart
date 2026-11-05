/// Built-in geometry uses a 1000×1000 reference space, scaled at execution.
/// 15 composition families × 8 geometric variants + one full-page layout.
class ComicLayoutTemplate {
  const ComicLayoutTemplate(
    this.id,
    this.name,
    this.purpose,
    this.tags,
    this.panels,
  );
  final String id, name, purpose;
  final List<String> tags;
  final List<Map<String, Object>> panels;
  List<Map<String, Object>> pixelPanels(int width, int height) => [
    for (final panel in panels)
      {
        ...panel,
        'box': [
          for (final (i, n) in (panel['box'] as List<int>).indexed)
            (n * (i.isEven ? width : height) / 1000).round(),
        ],
      },
  ];
}

Map<String, Object> _p(
  int l,
  int t,
  int r,
  int b, {
  Object? shape,
  String layer = 'back',
}) => {
  'box': [l, t, r, b],
  'layer': layer,
  'shape': ?shape,
};

List<Map<String, Object>> _rows(
  int count,
  int top,
  int bottom, {
  int left = 20,
  int right = 980,
  bool rtl = true,
}) {
  const gap = 16;
  final width = (right - left - gap * (count - 1)) / count;
  final panels = [
    for (var i = 0; i < count; i++)
      _p(
        (left + i * (width + gap)).round(),
        top,
        (left + i * (width + gap) + width).round(),
        bottom,
      ),
  ];
  return rtl ? panels.reversed.toList() : panels;
}

final List<ComicLayoutTemplate> comicLayouts = List.unmodifiable(_build());

List<ComicLayoutTemplate> _build() {
  final out = <ComicLayoutTemplate>[
    ComicLayoutTemplate(
      'L001',
      '整页定格',
      '关键揭示、高潮或完整空间；整页只有一个持续瞬间。',
      const ['揭示', '高潮', '空间'],
      [_p(0, 0, 1000, 1000)],
    ),
  ];
  void add(
    String name,
    String purpose,
    List<String> tags,
    List<Map<String, Object>> panels,
    int v,
  ) {
    out.add(
      ComicLayoutTemplate(
        'L${(out.length + 1).toString().padLeft(3, '0')}',
        '$name·${v + 1}',
        purpose,
        tags,
        panels,
      ),
    );
  }

  for (var family = 0; family < 15; family++) {
    for (var v = 0; v < 8; v++) {
      final cut = 230 + v * 65; // 230..685; real relative-area differences.
      final reverse = 1000 - cut;
      final mid = 370 + v * 35;
      switch (family) {
        case 0:
          add(
            '上下双拍',
            '两个瞬间的对照；调整前后拍的停留时间。',
            ['对白', '对照', '停顿'],
            [_p(20, 20, 980, cut), _p(20, cut + 16, 980, 980)],
            v,
          );
        case 1:
          add(
            '左右对峙',
            '人物或空间对照；右格先读，双方面积可不对等。',
            ['对峙', '对白'],
            [_p(cut + 16, 20, 980, 980), _p(20, 20, cut, 980)],
            v,
          );
        case 2:
          final second = cut + ((980 - cut) * .48).round();
          add(
            '横向三拍',
            '连续动作或细微表演；通过行高控制停顿。',
            ['连续动作', '等待', '表演'],
            [
              _p(20, 20, 980, cut),
              _p(20, cut + 16, 980, second),
              _p(20, second + 16, 980, 980),
            ],
            v,
          );
        case 3:
          final y1 = 155 + v * 15, y2 = 350 + v * 22, y3 = 620 + v * 12;
          add(
            '横向四拍',
            '渐进揭示、等待、逐步加压；允许同机位重复。',
            ['等待', '悬念', '表演'],
            [
              _p(20, 20, 980, y1),
              _p(20, y1 + 16, 980, y2),
              _p(20, y2 + 16, 980, y3),
              _p(20, y3 + 16, 980, 980),
            ],
            v,
          );
        case 4:
          add(
            '上方主画面',
            '先建立事件或空间，再以两格承接反应。',
            ['空间', '登场', '反应'],
            [_p(20, 20, 980, cut), ..._rows(2, cut + 16, 980)],
            v,
          );
        case 5:
          add(
            '下方揭示',
            '前两格蓄力，下方较完整画面揭示结果。',
            ['揭示', '高潮', '反转'],
            [..._rows(2, 20, reverse - 16), _p(20, reverse, 980, 980)],
            v,
          );
        case 6:
          add(
            '右侧纵向主格',
            '右侧人物或动作先占据视野，左侧两格反馈。',
            ['动作', '登场', '对峙'],
            [
              _p(cut + 16, 20, 980, 980),
              _p(20, 20, cut, 492),
              _p(20, 508, cut, 980),
            ],
            v,
          );
        case 7:
          add(
            '左侧纵向落点',
            '右侧两拍铺垫，左侧竖幅完成动作或情绪。',
            ['动作', '揭示', '情绪'],
            [
              _p(reverse + 16, 20, 980, 492),
              _p(reverse + 16, 508, 980, 980),
              _p(20, 20, reverse, 980),
            ],
            v,
          );
        case 8:
          add(
            '四格对话变奏',
            '两排对话或反应；重心可偏移，不机械交替景别。',
            ['对白', '反应', '日常'],
            [
              _p(cut + 16, 20, 980, mid),
              _p(20, 20, cut, mid),
              _p(cut + 16, mid + 16, 980, 980),
              _p(20, mid + 16, cut, 980),
            ],
            v,
          );
        case 9:
          add(
            '上景下三拍',
            '上方空间/动作接下方三个细节或反应。',
            ['空间', '多人', '反应'],
            [_p(20, 20, 980, cut), ..._rows(3, cut + 16, 980)],
            v,
          );
        case 10:
          add(
            '三拍后大景',
            '三个准备动作后以宽幅完成爆发或留白。',
            ['动作', '高潮', '静场'],
            [..._rows(3, 20, reverse - 16), _p(20, reverse, 980, 980)],
            v,
          );
        case 11:
          final y2 = cut + ((980 - cut) * .48).round();
          add(
            '六格连续段落',
            '密集交流或连续表演；用三排行高组织节拍。',
            ['对白', '推理', '连续动作'],
            [
              ..._rows(2, 20, cut),
              ..._rows(2, cut + 16, y2),
              ..._rows(2, y2 + 16, 980),
            ],
            v,
          );
        case 12:
          final y2 = cut + ((980 - cut) * .48).round();
          add(
            '主事件与四反应',
            '多人事件后分配四个反应/细节，避免信息挤在同格。',
            ['多人', '反应', '群像'],
            [
              _p(20, 20, 980, cut),
              ..._rows(2, cut + 16, y2),
              ..._rows(2, y2 + 16, 980),
            ],
            v,
          );
        case 13:
          final d = .04 + v * .012;
          add(
            '斜切动作三格',
            '动作方向明确时使用斜边；不能仅为装饰破坏读序。',
            ['动作', '冲击', '追逐'],
            [
              _p(
                20,
                20,
                980,
                cut,
                shape: [
                  [0.0, d],
                  [1.0, 0.0],
                  [1.0, 1.0],
                  [0.0, 1.0],
                ],
              ),
              _p(
                508,
                cut + 16,
                980,
                980,
                shape: [
                  [0.0, 0.0],
                  [1.0, d],
                  [1.0, 1.0],
                  [d, 1.0],
                ],
              ),
              _p(20, cut + 16, 492, 980),
            ],
            v,
          );
        case 14:
          final size = 210 + v * 25;
          add(
            '主场景与嵌入细节',
            '完整场景中叠加两处局部/反应；注意遮挡与读序。',
            ['空间', '静场', '细节'],
            [
              _p(20, 20, 980, 980),
              _p(960 - size, 40, 960, 40 + size, layer: 'front'),
              _p(
                40,
                960 - size,
                40 + size,
                960,
                shape: 'ellipse',
                layer: 'front',
              ),
            ],
            v,
          );
      }
    }
  }
  return out;
}

ComicLayoutTemplate comicLayoutById(String id) => comicLayouts.firstWhere(
  (layout) => layout.id == id,
  orElse: () => throw FormatException('AI选择了不存在的布局：$id'),
);

String comicLayoutMenu() => comicLayouts
    .map((l) {
      final geometry = l.panels
          .map(
            (p) =>
                (p['box'] as List<int>).map((n) => (n / 10).round()).join(','),
          )
          .join(';');
      return '${l.id}｜${l.name}｜${l.panels.length}格｜${l.tags.join('/')}｜阅读顺序外框百分比[$geometry]';
    })
    .join('\n');
