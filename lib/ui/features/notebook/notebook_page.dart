import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/services/notebook_store.dart';
import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';

/// 记事本:左边是本子,右边是打开的那个本子里的各条(名字 + 内容),打字就存。
class NotebookPage extends StatefulWidget {
  const NotebookPage({super.key, required this.store});

  final NotebookStore store;

  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<NotebookPage> {
  /// 打开的本子;没选过或被删了就是第一个。
  String? _open;

  NotebookStore get store => widget.store;

  void _newBook() {
    final id = store.addBook(tr('本子 {0}', [store.books.length + 1]));
    setState(() => _open = id);
  }

  Future<void> _removeBook(Notebook b) async {
    final empty = b.notes.every((n) => n.title.isEmpty && n.text.isEmpty);
    if (!empty &&
        !await confirmDelete(
          context,
          tr('删除「{0}」?', [b.name]),
          tr('本子里的 {0} 条都会删掉。', [b.notes.length]),
        )) {
      return;
    }
    store.removeBook(b.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final books = store.books;
        final open =
            books.where((b) => b.id == _open).firstOrNull ?? books.firstOrNull;
        return ColoredBox(
          color: PennaColors.bg,
          child: Column(
            children: [
              PennaBar(
                color: PennaColors.card,
                children: [
                  Icon(
                    Icons.sticky_note_2_outlined,
                    size: 15,
                    color: PennaColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tr('记事本'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  PennaButton(
                    label: tr('新建本子'),
                    icon: Icons.add,
                    borderColor: PennaColors.border,
                    onPressed: _newBook,
                  ),
                ],
              ),
              Expanded(
                child: books.isEmpty
                    ? Center(
                        child: Text(
                          tr('还没有本子'),
                          style: TextStyle(color: PennaColors.slate500),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _BookList(
                            books: books,
                            open: open!.id,
                            onOpen: (id) => setState(() => _open = id),
                            onRemove: _removeBook,
                          ),
                          Expanded(
                            child: _BookView(
                              key: ValueKey(open.id),
                              store: store,
                              book: open,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 左边的本子列表:点一下打开,右键删除。
class _BookList extends StatelessWidget {
  const _BookList({
    required this.books,
    required this.open,
    required this.onOpen,
    required this.onRemove,
  });

  final List<Notebook> books;
  final String open;
  final ValueChanged<String> onOpen;
  final ValueChanged<Notebook> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: PennaColors.sidebar,
        border: Border(right: BorderSide(color: PennaColors.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final b in books)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: GestureDetector(
                onSecondaryTapDown: (d) async {
                  final picked = await popMenu(context, d.globalPosition, [
                    tr('删除'),
                  ]);
                  if (picked != null) onRemove(b);
                },
                child: Material(
                  color: b.id == open ? PennaColors.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onOpen(b.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              b.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: b.id == open
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: b.id == open
                                    ? PennaColors.primary
                                    : PennaColors.text,
                              ),
                            ),
                          ),
                          Text(
                            '${b.notes.length}',
                            style: TextStyle(
                              fontSize: 11,
                              color: PennaColors.slate400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 右边:本子的名字(直接改)和里面的各条。
class _BookView extends StatelessWidget {
  const _BookView({super.key, required this.store, required this.book});

  final NotebookStore store;
  final Notebook book;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: _Input(
                fieldKey: const ValueKey('book-name'),
                value: book.name,
                hint: tr('本子的名字'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
                onChanged: (v) => store.renameBook(book.id, v),
              ),
            ),
            const SizedBox(width: 12),
            PennaButton(
              label: tr('加一条'),
              icon: Icons.add,
              borderColor: PennaColors.border,
              onPressed: () => store.addNote(book.id),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final (i, n) in book.notes.indexed)
          Padding(
            key: ValueKey(n.id),
            padding: const EdgeInsets.only(bottom: 10),
            child: _NoteCard(
              index: i,
              note: n,
              onTitle: (v) => store.updateNote(book.id, n.id, title: v),
              onText: (v) => store.updateNote(book.id, n.id, text: v),
              onRemove: () => store.removeNote(book.id, n.id),
            ),
          ),
      ],
    );
  }
}

/// 一条:上面是名字,下面是内容;右上角复制内容、删掉这条。
class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.index,
    required this.note,
    required this.onTitle,
    required this.onText,
    required this.onRemove,
  });

  final int index;
  final Note note;
  final ValueChanged<String> onTitle;
  final ValueChanged<String> onText;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Input(
                  fieldKey: ValueKey('note-title-$index'),
                  value: note.title,
                  hint: tr('名字'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  onChanged: onTitle,
                ),
              ),
              IconButton(
                tooltip: tr('复制'),
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded),
                onPressed: note.text.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: note.text));
                        showToast(context, tr('已复制'));
                      },
              ),
              IconButton(
                tooltip: tr('删除'),
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                onPressed: () async {
                  if (note.text.isNotEmpty &&
                      !await confirmDelete(
                        context,
                        tr('删除这一条?'),
                        note.title.isEmpty ? tr('内容会一起删掉。') : note.title,
                      )) {
                    return;
                  }
                  onRemove();
                },
              ),
            ],
          ),
          _Input(
            fieldKey: ValueKey('note-text-$index'),
            value: note.text,
            hint: tr('内容'),
            multiline: true,
            style: const TextStyle(fontSize: 13, height: 1.5),
            onChanged: onText,
          ),
        ],
      ),
    );
  }
}

/// 没有边框的输入框:看着像文字,点进去就能改。自己记着控制器,打字时光标不跳。
class _Input extends StatefulWidget {
  const _Input({
    required this.fieldKey,
    required this.value,
    required this.hint,
    required this.style,
    required this.onChanged,
    this.multiline = false,
  });

  final Key fieldKey;
  final String value;
  final String hint;
  final TextStyle style;
  final ValueChanged<String> onChanged;
  final bool multiline;

  @override
  State<_Input> createState() => _InputState();
}

class _InputState extends State<_Input> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      contextMenuBuilder: pennaTextMenu,
      style: widget.style.copyWith(color: PennaColors.text),
      minLines: widget.multiline ? 3 : 1,
      maxLines: widget.multiline ? null : 1,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: widget.style.copyWith(color: PennaColors.slate400),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
      ),
      onChanged: widget.onChanged,
    );
  }
}
