import 'dart:convert';
import 'dart:typed_data';

import '../../../l10n/l10n.dart';

// Florence-2 的纯逻辑部分:指令、分词器(BART 的字节级 BPE)、防重复、喂给模型的像素。
// 跑模型在 data/services/florence_engine.dart。照 NLapt 的 nlapt/local/florence.py 移植。

/// 要的五个文件(在模型文件夹里的名字)。
const florenceDecoder = 'decoder_model_merged.onnx';
const florenceVision = 'vision_encoder.onnx';
const florenceEmbed = 'embed_tokens.onnx';
const florenceEncoder = 'encoder_model.onnx';
const florenceTokenizer = 'tokenizer.json';
const florenceOnnx = [
  florenceDecoder,
  florenceVision,
  florenceEmbed,
  florenceEncoder,
];

/// 指令和界面上的名字,按显示的先后。
Map<String, String> get florenceTaskLabels => {
  '<GENERATE_TAGS>': tr('标签'),
  '<CAPTION>': tr('一句话'),
  '<DETAILED_CAPTION>': tr('详细'),
  '<MORE_DETAILED_CAPTION>': tr('很详细'),
  '<ANALYZE>': tr('构图分析'),
  '<MIXED_CAPTION>': tr('描述 + 标签'),
  '<MIXED_CAPTION_PLUS>': tr('描述 + 标签 + 构图'),
};

/// 官方的几个指令要换成固定的英文问句再分词(照官方 processing_florence2.py);
/// PromptGen 加的那几个原样喂。
const _taskPrompts = {
  '<CAPTION>': 'What does the image describe?',
  '<DETAILED_CAPTION>': 'Describe in detail what is shown in the image.',
  '<MORE_DETAILED_CAPTION>':
      'Describe with a paragraph what is shown in the image.',
};

String florencePrompt(String task) => _taskPrompts[task] ?? task;

const florenceBos = 0, florencePad = 1, florenceEos = 2;

/// 解码器第一步固定喂这个,第二步强制出 [florenceBos](模型配置里的规矩)。
const florenceDecoderStart = 2;
const florenceMaxTokens = 1024;
const florenceNoRepeatNgram = 3;
const florenceImageSize = 768;

/// 模型输出缺字时的报错。
class FlorenceException implements Exception {
  const FlorenceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// GPT-2 那张字节 ↔ 可见字符的对照表。
Map<int, String> _bytesToUnicode() {
  final printable = [
    for (var c = 0x21; c <= 0x7E; c++) c,
    for (var c = 0xA1; c <= 0xAC; c++) c,
    for (var c = 0xAE; c <= 0xFF; c++) c,
  ];
  final codes = [...printable];
  var shift = 0;
  for (var b = 0; b < 256; b++) {
    if (!printable.contains(b)) {
      printable.add(b);
      codes.add(256 + shift++);
    }
  }
  return {
    for (var i = 0; i < printable.length; i++)
      printable[i]: String.fromCharCode(codes[i]),
  };
}

/// GPT-2 预分词的 ASCII 版:要分词的只有上面那几句固定的英文指令。
// ponytail: 只认 ASCII;要让用户随便写指令时得换成完整的 \p{L} 写法。
final _pretoken = RegExp(
  r"'s|'t|'re|'ve|'m|'ll|'d| ?[A-Za-z]+| ?[0-9]+| ?[^\sA-Za-z0-9]+|\s+(?!\S)|\s+",
);

/// 最小的字节级 BPE 分词器,读 HuggingFace 的 tokenizer.json。
class FlorenceTokenizer {
  FlorenceTokenizer(
    Map<String, int> vocab,
    List<(String, String)> merges,
    Map<String, int> added,
  ) : _vocab = vocab,
      _ranks = {for (final (i, m) in merges.indexed) '${m.$1} ${m.$2}': i},
      _idToToken = {for (final e in vocab.entries) e.value: e.key},
      _idToAdded = {for (final e in added.entries) e.value: e.key};

  factory FlorenceTokenizer.parse(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final model = data['model'] as Map<String, dynamic>;
      return FlorenceTokenizer(
        (model['vocab'] as Map).cast<String, int>(),
        [
          for (final m in model['merges'] as List)
            m is String
                ? (
                    m.substring(0, m.indexOf(' ')),
                    m.substring(m.indexOf(' ') + 1),
                  )
                : ((m as List)[0] as String, m[1] as String),
        ],
        {
          for (final t in data['added_tokens'] as List? ?? const [])
            (t as Map)['content'] as String: t['id'] as int,
        },
      );
    } on Object {
      throw FlorenceException(tr('分词器文件坏了'));
    }
  }

  final Map<String, int> _vocab;
  final Map<String, int> _ranks;
  final Map<int, String> _idToToken;
  final Map<int, String> _idToAdded;
  final _byteEncoder = _bytesToUnicode();
  late final _byteDecoder = {
    for (final e in _byteEncoder.entries) e.value: e.key,
  };

  List<String> _bpe(String token) {
    var parts = token.split('');
    while (parts.length > 1) {
      int? bestRank;
      var best = -1;
      for (var i = 0; i < parts.length - 1; i++) {
        final rank = _ranks['${parts[i]} ${parts[i + 1]}'];
        if (rank != null && (bestRank == null || rank < bestRank)) {
          bestRank = rank;
          best = i;
        }
      }
      if (best < 0) break;
      final first = parts[best], second = parts[best + 1];
      final merged = <String>[];
      for (var i = 0; i < parts.length; i++) {
        if (i < parts.length - 1 &&
            parts[i] == first &&
            parts[i + 1] == second) {
          merged.add(first + second);
          i++;
        } else {
          merged.add(parts[i]);
        }
      }
      parts = merged;
    }
    return parts;
  }

  /// 文字的 id,不加首尾的特殊符号。
  List<int> encode(String text) => [
    for (final m in _pretoken.allMatches(text))
      for (final part in _bpe(
        utf8.encode(m[0]!).map((b) => _byteEncoder[b]!).join(),
      ))
        if (_vocab[part] case final id?)
          id
        else
          for (final c in part.split('')) ?_vocab[c],
  ];

  /// `<s> 指令 </s>`:官方处理器给指令套的样子。
  List<int> encodePrompt(String text) => [
    florenceBos,
    ...encode(text),
    florenceEos,
  ];

  /// id 变回文字,去掉 `<s>`、`</s>`、`<pad>`。
  String decode(List<int> ids) {
    final out = StringBuffer();
    final bytes = <int>[];
    void flush() {
      if (bytes.isEmpty) return;
      out.write(utf8.decode(bytes, allowMalformed: true));
      bytes.clear();
    }

    for (final id in ids) {
      if (id == florenceBos || id == florenceEos || id == florencePad) continue;
      final added = _idToAdded[id];
      if (added != null && !_vocab.containsKey(added)) {
        flush();
        out.write(added);
        continue;
      }
      for (final c in (_idToToken[id] ?? '').split('')) {
        final b = _byteDecoder[c];
        if (b != null) bytes.add(b);
      }
    }
    flush();
    return out.toString();
  }
}

/// 下一步不能出的 id:出了就会重复一个已经出现过的 [n] 连词(HuggingFace 的规矩)。
Set<int> bannedNext(List<int> generated, [int n = florenceNoRepeatNgram]) {
  if (n <= 0 || generated.length < n) return const {};
  final prefix = generated.sublist(generated.length - (n - 1));
  final banned = <int>{};
  for (var start = 0; start + n <= generated.length; start++) {
    var same = true;
    for (var k = 0; k < n - 1; k++) {
      if (generated[start + k] != prefix[k]) {
        same = false;
        break;
      }
    }
    if (same) banned.add(generated[start + n - 1]);
  }
  return banned;
}

/// 把 [size]×[size] 的 RGBA(已经拉伸好)变成模型要的 (1, 3, size, size):
/// 0~1 后按 ImageNet 的均值方差归一化,透明的地方算白色。
Float32List florencePixels(Uint8List rgba, int size) {
  const mean = [0.485, 0.456, 0.406], std = [0.229, 0.224, 0.225];
  final plane = size * size;
  final out = Float32List(plane * 3);
  for (var i = 0; i < plane; i++) {
    final a = rgba[i * 4 + 3] / 255;
    for (var c = 0; c < 3; c++) {
      final v = (rgba[i * 4 + c] * a + 255 * (1 - a)) / 255;
      out[c * plane + i] = (v - mean[c]) / std[c];
    }
  }
  return out;
}

/// 在一行打分里挑最大的那个,跳过 [banned]。
int argmaxExcept(List<double> row, Set<int> banned) {
  var best = -1;
  var top = double.negativeInfinity;
  for (var i = 0; i < row.length; i++) {
    if (row[i] > top && !banned.contains(i)) {
      top = row[i];
      best = i;
    }
  }
  return best;
}
