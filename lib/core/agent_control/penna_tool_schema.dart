/// MCP 工具清单；所有修改都由 Penna 本体校验并执行。
const _integer = {'type': 'integer'};
const _string = {'type': 'string'};
const _identity = {
  'series': _integer,
  'page_number': {'type': 'integer', 'minimum': 1},
};
const _shape = {
  'description': '可选形状：ellipse 为椭圆；rect 或 null 恢复矩形；多边形用3–16个[x,y]顶点，坐标是相对本框的0–1比例，不是画布像素。形状用于画板和存档；当前整页MOSS不会按shape精确裁切，需在caption描述轮廓。',
  'anyOf': [
    {
      'type': 'string',
      'enum': ['ellipse', 'rect'],
    },
    {'type': 'null'},
    {
      'type': 'array',
      'minItems': 3,
      'maxItems': 16,
      'items': {
        'type': 'array',
        'minItems': 2,
        'maxItems': 2,
        'items': {'type': 'number', 'minimum': 0, 'maximum': 1},
      },
    },
  ],
};
const _layout = {
  'type': 'object',
  'description': 'Penna Layout 格式：width/height、caption/style、cast 角色卡、canvas(single/multi_panel/collage)、boxes。每个 box 用 box:[left,top,right,bottom] 整数像素，label:object/character/text，caption 描述，text 台词，name 中文名，layer:back/middle/front。shape 支持 ellipse、rect/null 或3–16个0–1归一化顶点。它用于画板和存档，当前整页MOSS不按shape精确裁切；斜边等轮廓还应写入caption。请先 get_page 读取示例。',
  'required': ['width', 'height', 'boxes'],
  'properties': {
    'width': {'type': 'integer', 'minimum': 64, 'maximum': 4096},
    'height': {'type': 'integer', 'minimum': 64, 'maximum': 4096},
    'caption': _string,
    'style': _string,
    'cast': {'type': 'object', 'additionalProperties': _string},
    'canvas': {
      'enum': ['single', 'multi_panel', 'collage'],
    },
    'boxes': {
      'type': 'array',
      'maxItems': 500,
      'items': {
        'type': 'object',
        'required': ['box'],
        'properties': {
          'box': {
            'type': 'array',
            'items': _integer,
            'minItems': 4,
            'maxItems': 4,
          },
          'label': {
            'enum': ['object', 'character', 'text'],
          },
          'caption': _string,
          'text': _string,
          'name': _string,
          'shape': _shape,
          'layer': {
            'enum': ['back', 'middle', 'front'],
          },
        },
      },
    },
  },
};
Map<String, Object?> _tool(
  String name,
  String description,
  Map<String, Object?> properties,
  List<String> required,
) => {
  'name': name,
  'description': description,
  'inputSchema': {
    'type': 'object',
    'properties': properties,
    'required': required,
    'additionalProperties': false,
  },
};
List<Map<String, Object?>> pennaToolSchema() => [
  _tool('penna_status', '读取连接、当前系列和页面、任务状态。不调用内置聊天模型。', {}, []),
  _tool('penna_list_pages', '列出分镜页及版本号；series 省略时列全部。', {
    'series': _integer,
  }, []),
  _tool('penna_get_page', '读取指定页完整布局、角色卡、版本号。修改前必须先读。', _identity, [
    'series',
    'page_number',
  ]),
  _tool(
    'penna_create_page',
    '新增分镜页，保留用户当前选中页。未传 series 时加入当前系列；new_series=true 新建系列。',
    {
      'series': _integer,
      'name': _string,
      'series_name': _string,
      'new_series': {'type': 'boolean'},
      'layout': _layout,
    },
    ['layout'],
  ),
  _tool(
    'penna_update_page',
    '修改一页。expected_revision 必须来自最新 get_page；冲突时重新读取。未改内容请保留。',
    {
      ..._identity,
      'expected_revision': _string,
      'name': _string,
      'layout': _layout,
    },
    ['series', 'page_number', 'expected_revision', 'layout'],
  ),
  _tool('penna_list_loras', '从已运行的 ComfyUI 读取可用 LoRA 文件名。', {}, []),
  _tool(
    'penna_submit_render',
    '冻结指定页并串行出图，立即返回 task_id，随后用 get_task 查询。单页修改后只传该页页码。',
    {
      'series': _integer,
      'page_numbers': {
        'type': 'array',
        'minItems': 1,
        'uniqueItems': true,
        'items': {'type': 'integer', 'minimum': 1},
      },
      'settings': {
        'type': 'object',
        'properties': {
          'steps': {'type': 'integer', 'minimum': 1, 'maximum': 100},
          'seed': {'type': 'integer', 'minimum': 0},
          'cfg': {'type': 'number', 'minimum': 0, 'maximum': 20},
          'bubble': {
            'enum': ['oval', 'cloud', 'spiky'],
          },
          'loras': {
            'type': 'array',
            'items': {
              'type': 'object',
              'required': ['name', 'strength'],
              'properties': {
                'name': _string,
                'strength': {'type': 'number', 'minimum': 0, 'maximum': 2},
              },
            },
          },
        },
      },
    },
    ['series', 'page_numbers'],
  ),
  _tool('penna_get_task', '查询出图任务阶段、结果和错误。', {'task_id': _string}, ['task_id']),
  _tool(
    'penna_list_results',
    '查找指定系列成品。标记是否匹配当前分镜，可读取旧版本但不冒充新稿。',
    {'series': _integer},
    ['series'],
  ),
  _tool(
    'penna_export_comic',
    '将指定系列的当前分镜成品按页码导出到配置的成品目录/exports；缺页则报错。',
    {
      'series': _integer,
      'title': _string,
      'formats': {
        'type': 'array',
        'minItems': 1,
        'items': {
          'enum': ['cbz', 'pdf'],
        },
      },
      'reading_direction': {
        'enum': ['rtl', 'ltr'],
      },
    },
    ['series', 'title'],
  ),
];
