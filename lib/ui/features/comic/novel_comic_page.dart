import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'comic_preview.dart';
import 'novel_comic_model.dart';
import 'novel_assets_panel.dart';
import 'novel_prompt_output.dart';
import 'comic_layout_gallery.dart';
import '../layout/penna_relay_dialog.dart';
import '../layout/comic_finished_preview.dart';

class NovelComicPage extends StatefulWidget {
  const NovelComicPage({super.key, required this.model});
  final NovelComicModel model;
  @override
  State<NovelComicPage> createState() => _NovelComicPageState();
}

class _NovelComicPageState extends State<NovelComicPage> {
  NovelComicModel get model => widget.model;
  int _tab = 0;
  String? _panel;

  Future<void> _import() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: '小说', extensions: ['txt', 'epub']),
        ],
      );
      if (file == null || !mounted) return;
      await model.importNovel(file.path);
    } on Object catch (e) {
      if (mounted) showToast(context, '导入失败：$e', warn: true);
    }
  }

  Future<void> _plan({bool restart = false}) async {
    final ai = model.options.planner == 'ai';
    final replan =
        restart ||
        (model.current?.pages.isNotEmpty == true &&
            (!ai || !model.canResumeAi));
    if (replan) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('重新生成分镜？')),
          content: Text(
            tr('AI模式会新建一轮排版，旧页面文件保留。规则模式沿用原来的离线规划行为。续做未完成任务无需重新规划。'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('继续生成分镜')),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    await model.planCurrent(restart: replan);
    if (mounted) {
      setState(() {
        _tab = 0;
        _panel = null;
      });
      if (ai && model.error == null && model.current?.status == 'planned') {
        await _deliver();
      }
    }
  }

  Future<void> _deliver() async {
    if (model.options.deliveryMode == 'copy') {
      setState(() => _tab = 5);
    } else {
      await _relay();
    }
  }

  Future<void> _assets() async {
    await model.prepareAssetsCurrent();
    if (mounted) setState(() => _tab = 4);
  }

  Future<void> _revise() async {
    String instruction = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI重设计当前页'),
        content: SizedBox(
          width: 520,
          child: TextField(
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '修改要求',
              hintText: '例如：用更强的留白突出孤独，保持角色服装和原有剧情。',
            ),
            onChanged: (v) => instruction = v,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重设计当前页'),
          ),
        ],
      ),
    );
    if (confirmed == true && instruction.trim().isNotEmpty) {
      await model.redesignCurrentPage(instruction.trim());
    }
  }

  Future<void> _relay({bool preview = false}) async {
    try {
      final snapshot = await model.relaySnapshot();
      if (!mounted) return;
      if (preview) {
        await showComicFinishedPreview(
          context,
          snapshots: (snapshot['series_pages'] as List)
              .cast<Map<String, Object?>>(),
          title: model.current!.name,
          initialPage: model.current!.pages.indexOf(model.currentPage!),
          onEditPage: _editPage,
        );
      } else {
        await showPennaRelay(
          context,
          snapshot: snapshot,
          onEditPage: _editPage,
        );
      }
    } on Object catch (e) {
      if (mounted) showToast(context, '$e', warn: true);
    }
  }

  void _editPage(int index) {
    if (index < 0 || index >= model.current!.pages.length) return;
    model.selectPage(model.current!.pages[index].id);
    setState(() => _tab = 2);
  }

  Future<void> _settings() async {
    var draft = model.options;
    String? problem;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(tr('小说漫画设置')),
          content: SizedBox(
            width: 530,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr('AI按原文逐页选择布局，使用API管理中的连接。生成后可接力出图，台词由模型绘制。'),
                    style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: draft.planner,
                    decoration: const InputDecoration(labelText: '分镜方式'),
                    items: const [
                      DropdownMenuItem(
                        value: 'ai',
                        child: Text('AI创作与布局匹配（121套）'),
                      ),
                      DropdownMenuItem(
                        value: 'rules',
                        child: Text('离线规则分镜（兼容旧版）'),
                      ),
                    ],
                    onChanged: (v) =>
                        setDialog(() => draft = draft.copyWith(planner: v)),
                  ),
                  if (draft.planner == 'ai') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: draft.deliveryMode,
                      decoration: const InputDecoration(labelText: '交付方式（二选一）'),
                      items: const [
                        DropdownMenuItem(value: 'copy', child: Text('自行复制提示词')),
                        DropdownMenuItem(
                          value: 'workflow',
                          child: Text('用我的工作流出图'),
                        ),
                      ],
                      onChanged: (v) => setDialog(
                        () => draft = draft.copyWith(deliveryMode: v),
                      ),
                    ),
                    if (draft.deliveryMode == 'workflow') ...[
                      const SizedBox(height: 12),
                      PennaField(
                        key: ValueKey('novel-workflow-${draft.workflowPath}'),
                        label: '工作流路径（兼容的MOSS API JSON；留空沿用漫画连接）',
                        value: draft.workflowPath,
                        onChanged: (v) =>
                            draft = draft.copyWith(workflowPath: v),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final file = await openFile(
                            acceptedTypeGroups: [
                              const XTypeGroup(
                                label: 'ComfyUI API工作流',
                                extensions: ['json'],
                              ),
                            ],
                          );
                          if (file != null && context.mounted) {
                            setDialog(
                              () => draft = draft.copyWith(
                                workflowPath: file.path,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.folder_open),
                        label: const Text('选择我的工作流'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue:
                          model.aiProfiles.any((p) => p.id == draft.llmId)
                          ? draft.llmId
                          : '',
                      decoration: const InputDecoration(labelText: 'AI模型连接'),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('跟随API管理中当前选中的连接'),
                        ),
                        for (final p in model.aiProfiles)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: (v) => draft = draft.copyWith(llmId: v),
                    ),
                    const SizedBox(height: 12),
                    PennaField(
                      label: '创作要求',
                      value: draft.creativeBrief,
                      maxLines: 5,
                      onChanged: (v) =>
                          draft = draft.copyWith(creativeBrief: v),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '格数由AI选择的布局决定。这里生成文字方案与真实几何排版，未进行成图视觉审阅。',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: draft.style,
                    decoration: InputDecoration(labelText: tr('画风')),
                    items: const [
                      DropdownMenuItem(value: 'mono', child: Text('黑白漫画')),
                      DropdownMenuItem(value: 'color', child: Text('彩色漫画')),
                      DropdownMenuItem(value: 'sketch', child: Text('线稿')),
                    ],
                    onChanged: (value) => setDialog(
                      () => draft = draft.copyWith(
                        style: value,
                        lora: value == 'color'
                            ? 'muqiu_moss.safetensors'
                            : 'moss_Lineart.safetensors',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: PennaField(
                          label: tr('每章页数'),
                          value: '${draft.pagesPerChapter}',
                          onChanged: (v) => draft = draft.copyWith(
                            pagesPerChapter: int.tryParse(v) ?? 0,
                          ),
                        ),
                      ),
                      if (draft.planner == 'rules') ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: draft.panelsPerPage,
                            decoration: InputDecoration(labelText: tr('每页格数')),
                            items: [
                              for (final n in [4, 5, 6])
                                DropdownMenuItem(value: n, child: Text('$n 格')),
                            ],
                            onChanged: (v) =>
                                draft = draft.copyWith(panelsPerPage: v),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  PennaField(
                    key: ValueKey('lora-${draft.style}'),
                    label: 'LoRA',
                    value: draft.lora,
                    onChanged: (v) => draft = draft.copyWith(lora: v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: PennaField(
                          label: tr('LoRA 强度'),
                          value: '${draft.loraStrength}',
                          onChanged: (v) => draft = draft.copyWith(
                            loraStrength: double.tryParse(v) ?? -1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PennaField(
                          label: tr('步数'),
                          value: '${draft.steps}',
                          onChanged: (v) => draft = draft.copyWith(
                            steps: int.tryParse(v) ?? 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PennaField(
                          label: tr('种子'),
                          value: '${draft.seed}',
                          onChanged: (v) => draft = draft.copyWith(
                            seed: int.tryParse(v) ?? -1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  PennaField(
                    label: 'MOSS CFG',
                    value: '${draft.cfg}',
                    onChanged: (v) =>
                        draft = draft.copyWith(cfg: double.tryParse(v) ?? -1),
                  ),
                  const SizedBox(height: 12),
                  if (draft.planner == 'rules')
                    PennaField(
                      label: tr('ComfyUI 地址'),
                      value: draft.comfyUrl,
                      onChanged: (v) => draft = draft.copyWith(comfyUrl: v),
                    )
                  else
                    const Text(
                      'ComfyUI地址沿用“设置 → 漫画连接”。接力面板中可继续多选LoRA并调整最终参数。',
                      style: TextStyle(fontSize: 11),
                    ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: Text(
                      tr('本地后端'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      PennaField(
                        label: tr('Python 路径'),
                        value: draft.python,
                        onChanged: (v) => draft = draft.copyWith(python: v),
                      ),
                      const SizedBox(height: 12),
                      PennaField(
                        label: tr('launcher.py 路径'),
                        value: draft.launcher,
                        onChanged: (v) => draft = draft.copyWith(launcher: v),
                      ),
                    ],
                  ),
                  if (problem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        problem!,
                        style: TextStyle(color: PennaColors.diffDelText),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('取消')),
            ),
            FilledButton(
              onPressed: () {
                try {
                  model.setOptions(draft);
                  Navigator.pop(context);
                } on Object catch (e) {
                  setDialog(() => problem = '$e');
                }
              },
              child: Text(tr('保存')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final current = model.current;
      return Material(
        color: PennaColors.bg,
        child: Column(
          children: [
            PennaBar(
              color: PennaColors.card,
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 17,
                  color: PennaColors.primary,
                ),
                const SizedBox(width: 7),
                Text(
                  tr('小说漫画'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                if (current != null)
                  Expanded(
                    child: Text(
                      current.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: PennaColors.slate500,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (model.options.planner == 'ai') ...[
                  PennaButton(
                    label: '准备资产',
                    icon: Icons.people_alt_outlined,
                    onPressed: current == null || model.busy ? null : _assets,
                  ),
                  const SizedBox(width: 6),
                ],
                PennaButton(
                  label: tr('导入小说'),
                  icon: Icons.upload_file_outlined,
                  onPressed: model.busy ? null : _import,
                ),
                const SizedBox(width: 6),
                PennaButton(
                  label: tr(
                    model.options.planner == 'ai'
                        ? model.canResumeAi
                              ? '继续AI排版'
                              : 'AI自动排版'
                        : '生成分镜',
                  ),
                  icon: Icons.auto_awesome_outlined,
                  background: PennaColors.primaryBg,
                  foreground: PennaColors.primary,
                  onPressed: current == null || model.busy
                      ? null
                      : () => _plan(),
                ),
                if (model.busy && model.options.planner == 'ai')
                  IconButton(
                    tooltip: '暂停AI排版',
                    onPressed: model.pauseAi,
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
                IconButton(
                  tooltip: '121套布局目录',
                  onPressed: () => showComicLayoutGallery(context),
                  icon: const Icon(Icons.dashboard_customize_outlined),
                ),
                if (model.page?['layout'] != null) ...[
                  IconButton(
                    tooltip: 'AI修改当前页',
                    onPressed: model.busy ? null : _revise,
                    icon: const Icon(Icons.edit_note),
                  ),
                  IconButton(
                    tooltip: '一键接力出图',
                    onPressed: model.busy ? null : () => _relay(),
                    icon: const Icon(Icons.play_circle_outline),
                  ),
                  IconButton(
                    tooltip: '成品预览与导出',
                    onPressed: model.busy ? null : () => _relay(preview: true),
                    icon: const Icon(Icons.menu_book_outlined),
                  ),
                ],
                if (current != null && current.pages.isNotEmpty)
                  IconButton(
                    tooltip: '重新规划（保留旧文件）',
                    onPressed: model.busy ? null : () => _plan(restart: true),
                    icon: const Icon(Icons.restart_alt),
                  ),
                const SizedBox(width: 6),
                PennaButton(
                  label: '',
                  icon: Icons.tune,
                  tooltip: tr('小说漫画设置'),
                  onPressed: model.busy ? null : _settings,
                ),
              ],
            ),
            if (model.options.planner == 'ai')
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    const Text('交付方式：'),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'copy',
                          label: Text('自行复制提示词'),
                          icon: Icon(Icons.copy),
                        ),
                        ButtonSegment(
                          value: 'workflow',
                          label: Text('用我的工作流'),
                          icon: Icon(Icons.play_arrow),
                        ),
                      ],
                      selected: {model.options.deliveryMode},
                      onSelectionChanged: model.busy
                          ? null
                          : (set) => model.setOptions(
                              model.options.copyWith(deliveryMode: set.single),
                            ),
                    ),
                    const Spacer(),
                    if (model.page?['layout'] != null)
                      TextButton(
                        onPressed: model.busy ? null : _deliver,
                        child: Text(
                          model.options.deliveryMode == 'copy'
                              ? '查看/复制当前页提示词'
                              : '用工作流出图',
                        ),
                      ),
                  ],
                ),
              ),
            if (model.busy) const LinearProgressIndicator(minHeight: 2),
            if (model.error != null)
              Container(
                width: double.infinity,
                color: PennaColors.diffDel,
                padding: const EdgeInsets.all(10),
                child: SelectableText(
                  model.error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: PennaColors.diffDelText,
                  ),
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1120;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth < 850 ? 180 : 226,
                        child: _library(),
                      ),
                      VerticalDivider(width: 1, color: PennaColors.border),
                      Expanded(
                        child: current == null ? _empty() : _workspace(wide),
                      ),
                      if (wide && model.page != null && _tab != 4) ...[
                        VerticalDivider(width: 1, color: PennaColors.border),
                        SizedBox(width: 320, child: _inspector()),
                      ],
                    ],
                  );
                },
              ),
            ),
            Container(
              height: 30,
              color: PennaColors.card,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Icons.edit_note, size: 14, color: PennaColors.slate500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      model.progress.isNotEmpty
                          ? model.progress
                          : tr('AI逐页设计 · 121套布局匹配 · 台词交给模型 · 可接力出图'),
                      style: TextStyle(
                        fontSize: 11,
                        color: PennaColors.slate500,
                      ),
                    ),
                  ),
                  if (current != null)
                    Text(
                      '${current.pages.length} 页分镜',
                      style: TextStyle(
                        fontSize: 11,
                        color: PennaColors.slate500,
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

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 48,
            color: PennaColors.primary,
          ),
          const SizedBox(height: 20),
          Text(
            tr('从一部小说开始'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            tr('导入 TXT 或 EPUB，按卷章整理内容，再生成可编辑的漫画分镜。'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: PennaColors.slate500,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 24),
          PennaButton(
            label: tr('导入小说'),
            icon: Icons.upload_file_outlined,
            background: PennaColors.primaryBg,
            foreground: PennaColors.primary,
            onPressed: _import,
          ),
        ],
      ),
    ),
  );

  Widget _library() {
    final project = model.current;
    return Material(
      color: PennaColors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: Text(
              tr('作品'),
              style: TextStyle(fontSize: 12, color: PennaColors.slate500),
            ),
          ),
          if (model.projects.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                tr('导入后在这里管理卷章和页面'),
                style: TextStyle(
                  fontSize: 12,
                  color: PennaColors.slate400,
                  height: 1.6,
                ),
              ),
            ),
          if (model.projects.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in model.projects)
                    ListTile(
                      dense: true,
                      selected: p.id == project?.id,
                      selectedTileColor: PennaColors.primaryBg,
                      leading: Icon(
                        Icons.menu_book,
                        size: 18,
                        color: PennaColors.primary,
                      ),
                      title: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        p.pages.isEmpty ? tr('等待规划') : '${p.pages.length} 页分镜',
                        style: const TextStyle(fontSize: 10),
                      ),
                      onTap: model.busy
                          ? null
                          : () => model.selectProject(p.id),
                    ),
                ],
              ),
            ),
          Divider(height: 24, color: PennaColors.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              tr('卷章 / 页面'),
              style: TextStyle(fontSize: 12, color: PennaColors.slate500),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: project == null || project.pages.isEmpty
                ? const SizedBox()
                : ListView(
                    children: [
                      for (final volume
                          in project.pages.map((p) => p.volume).toSet())
                        ExpansionTile(
                          initiallyExpanded: true,
                          dense: true,
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          title: Text(
                            volume,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          children: [
                            for (final chapter
                                in project.pages
                                    .where((p) => p.volume == volume)
                                    .map((p) => p.chapter)
                                    .toSet())
                              ExpansionTile(
                                initiallyExpanded: true,
                                dense: true,
                                tilePadding: const EdgeInsets.only(
                                  left: 20,
                                  right: 10,
                                ),
                                title: Text(
                                  chapter,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                children: [
                                  for (final p in project.pages.where(
                                    (p) =>
                                        p.volume == volume &&
                                        p.chapter == chapter,
                                  ))
                                    ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.only(
                                        left: 32,
                                        right: 10,
                                      ),
                                      selected: model.currentPage?.id == p.id,
                                      selectedTileColor: PennaColors.primaryBg,
                                      title: Text(
                                        p.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      trailing: Icon(
                                        Icons.radio_button_unchecked,
                                        size: 12,
                                        color: PennaColors.slate400,
                                      ),
                                      onTap: model.busy
                                          ? null
                                          : () {
                                              _panel = null;
                                              model.selectPage(p.id);
                                            },
                                    ),
                                ],
                              ),
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _workspace(bool wide) {
    if (_tab == 4 && model.current != null) return _assetLibrary();
    if (model.page == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.view_quilt_outlined,
                size: 42,
                color: PennaColors.slate400,
              ),
              const SizedBox(height: 16),
              Text(
                tr('小说已导入'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr('先准备文字角色、场景和道具资产，再由AI逐页选择布局。'),
                style: TextStyle(color: PennaColors.slate500),
              ),
              const SizedBox(height: 12),
              SelectableText(
                model.current!.inputPath,
                style: TextStyle(fontSize: 11, color: PennaColors.slate400),
              ),
            ],
          ),
        ),
      );
    }
    final panels = _items('panel');
    final selected =
        panels.where((p) => p['id'] == _panel).firstOrNull ??
        panels.firstOrNull;
    return Column(
      children: [
        Container(
          height: 45,
          color: PennaColors.card,
          child: Row(
            children: [
              const SizedBox(width: 10),
              for (final entry in [
                (0, '漫画页'),
                (1, '原文'),
                (2, '分镜编辑'),
                (3, '待生成'),
                (4, '文字资产'),
                (5, '提示词'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TextButton(
                    onPressed: () => setState(() => _tab = entry.$1),
                    style: TextButton.styleFrom(
                      foregroundColor: _tab == entry.$1
                          ? PennaColors.primary
                          : PennaColors.slate500,
                    ),
                    child: Text(
                      tr(entry.$2),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            5 => NovelPromptOutput(model: model),
            1 => SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: SelectableText(
                model.page?['source_text'] as String? ??
                    panels
                        .map((p) => p['source_text'] as String? ?? '')
                        .join('\n\n'),
                style: TextStyle(
                  fontFamily: bundledCjkFont,
                  fontSize: 14,
                  height: 1.9,
                  color: PennaColors.text,
                ),
              ),
            ),
            2 => _inspector(all: true),
            3 => _queue(),
            _ => ComicPreview(
              page: model.page!,
              selected: selected?['id'] as String?,
              onSelect: (id) => setState(() {
                _panel = id;
                if (!wide) _tab = 2;
              }),
            ),
          },
        ),
        if (model.current!.warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              model.current!.warnings.join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: PennaColors.lockText),
            ),
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _items(String type) => [
    for (final raw in model.page?['items'] as List? ?? [])
      if (raw['type'] == type) Map<String, dynamic>.from(raw as Map),
  ];

  Widget _inspector({bool all = false}) {
    final panels = _items('panel');
    final selected =
        panels.where((p) => p['id'] == _panel).firstOrNull ??
        panels.firstOrNull;
    final shown = all ? panels : [?selected];
    return Material(
      color: PennaColors.card,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text(
                tr('分镜与台词'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              PennaButton(
                label: tr('复制 JSON'),
                icon: Icons.copy,
                onPressed: model.page == null
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: const JsonEncoder.withIndent('  ')
                                .convert(model.page),
                          ),
                        );
                        if (mounted) showToast(context, tr('已复制页面 JSON'));
                      },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr('修改后自动保存。画面生成前可逐格检查。'),
            style: TextStyle(fontSize: 11, color: PennaColors.slate500),
          ),
          if (model.page?['layout_id'] != null) ...[
            const SizedBox(height: 12),
            Text(
              '${model.page!['layout_id']} · ${model.page!['layout_name']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '${model.page!['layout_reason']}',
              style: const TextStyle(fontSize: 12),
            ),
            if (model.page!['alternatives'] is List)
              ExpansionTile(
                title: const Text(
                  'AI比较过的文字构图思路',
                  style: TextStyle(fontSize: 12),
                ),
                children: [
                  Text(
                    (model.page!['alternatives'] as List).join('\n'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            const Text(
              '仅完成文字方案与排版，尚未进行成图视觉验收。',
              style: TextStyle(fontSize: 11),
            ),
          ],
          if (!all) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var n = 0; n < panels.length; n++)
                  ChoiceChip(
                    label: Text('${n + 1}'),
                    selected: panels[n]['id'] == selected?['id'],
                    onSelected: (_) =>
                        setState(() => _panel = panels[n]['id'] as String),
                  ),
              ],
            ),
          ],
          for (final panel in shown) ...[
            const SizedBox(height: 18),
            Text(
              '第 ${panels.indexOf(panel) + 1} 格 · ${panel['shape']}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: PennaColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('${model.currentPage?.id}-${panel['id']}-camera'),
              initialValue: panel['camera'] as String? ?? 'wide',
              decoration: InputDecoration(labelText: tr('镜头')),
              items: [
                for (final entry in [
                  ('wide', '全景'),
                  ('medium', '中景'),
                  ('close', '特写'),
                  ('low', '仰视'),
                  ('high', '俯视'),
                  ('detail', '局部细节'),
                  ('over_shoulder', '过肩'),
                  ('subjective', '主观视角'),
                ])
                  DropdownMenuItem(value: entry.$1, child: Text(entry.$2)),
              ],
              onChanged: (value) {
                if (value != null) {
                  model.editItem(panel['id'] as String, 'camera', value);
                }
              },
            ),
            const SizedBox(height: 12),
            PennaField(
              key: ValueKey('${model.currentPage?.id}-${panel['id']}-desc'),
              label: tr('画面描述'),
              value: panel['desc'] as String? ?? '',
              maxLines: 7,
              onChanged: (value) =>
                  model.editItem(panel['id'] as String, 'desc', value),
            ),
            const SizedBox(height: 12),
            for (final bubble in _items(
              'bubble',
            ).where((b) => b['panel_id'] == panel['id'])) ...[
              PennaField(
                key: ValueKey('${model.currentPage?.id}-${bubble['id']}-text'),
                label: tr('中文台词'),
                value: bubble['text'] as String? ?? '',
                maxLines: 3,
                onChanged: (value) =>
                    model.editItem(bubble['id'] as String, 'text', value),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('${model.currentPage?.id}-${bubble['id']}-kind'),
                initialValue: bubble['kind'] as String? ?? 'speech-notail',
                decoration: InputDecoration(labelText: tr('气泡')),
                items: [
                  for (final entry in [
                    ('speech-notail', '画外对白'),
                    ('speech', '椭圆对白'),
                    ('thought', '云朵内心'),
                    ('shout', '锯齿喊叫'),
                    ('narration', '旁白'),
                  ])
                    DropdownMenuItem(value: entry.$1, child: Text(entry.$2)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    model.editItem(bubble['id'] as String, 'kind', value);
                  }
                },
              ),
              const SizedBox(height: 14),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(tr('本格原文'), style: const TextStyle(fontSize: 12)),
              children: [
                SelectableText(
                  panel['source_text'] as String? ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: PennaColors.slate500,
                  ),
                ),
              ],
            ),
            Divider(color: PennaColors.border),
          ],
        ],
      ),
    );
  }

  Widget _assetLibrary() => NovelAssetsPanel(
    model: model,
    onBack: () => setState(() => _tab = 0),
    onPlan: () => _plan(),
  );

  Widget _queue() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        tr('待生成页面'),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      Text(
        tr('点击上方“一键接力出图”，可生成当前页或勾选多页。逐格模式按漫画格作真实蒙版拼接。'),
        style: TextStyle(fontSize: 12, color: PennaColors.slate500),
      ),
      const SizedBox(height: 16),
      for (final p in model.current!.pages)
        ListTile(
          dense: true,
          leading: Icon(
            Icons.hourglass_empty,
            size: 18,
            color: PennaColors.slate400,
          ),
          title: Text(p.title, style: const TextStyle(fontSize: 12)),
          subtitle: Text(
            '${p.volume} / ${p.chapter}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Text(
            tr('待生成'),
            style: TextStyle(fontSize: 11, color: PennaColors.slate500),
          ),
        ),
      const SizedBox(height: 18),
      Text(
        tr('作品输出目录'),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      SelectableText(
        model.current!.outputPath,
        style: TextStyle(fontSize: 11, color: PennaColors.slate500),
      ),
    ],
  );
}
