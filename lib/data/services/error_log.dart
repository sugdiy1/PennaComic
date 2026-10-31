import 'dart:io';

/// 把出错的信息追加到一个文件里(「文档\Penna\error.log」),用户报 bug 时有东西可看。
class ErrorLog {
  ErrorLog(this.file, {Iterable<String> Function()? secrets})
    : _secrets = secrets ?? (() => const []);

  final File file;

  /// 写之前把这些字符串(Key、令牌)换成 ***,日志发给别人也不漏。
  final Iterable<String> Function() _secrets;

  /// 超过这么大就把旧日志挪成 .old(只留一份),免得越写越大。
  static const maxBytes = 512 * 1024;

  void write(String message) {
    var text = '[${DateTime.now().toIso8601String()}] $message\n';
    for (final s in _secrets()) {
      // 太短的值换掉会误伤正文。
      if (s.length >= 6) text = text.replaceAll(s, '***');
    }
    try {
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() > maxBytes) {
        file.renameSync('${file.path}.old');
      }
      file.writeAsStringSync(text, mode: FileMode.append, flush: true);
    } on FileSystemException {
      // 日志都写不了就算了:这里再抛只会出更多错。
    }
  }
}
