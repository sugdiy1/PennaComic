// 生成的文件:取自 NLapt 的 nlapt/local/catalog.py(快照 2026-09-14),大小和 SHA256 都是 HuggingFace 上的原值。
// 改清单时照那边重新生成,别手改数字。只收能看图的模型(纯文本的反推不了图)。

/// 一个要下载的文件:仓库里的路径、大小、SHA256。
typedef ModelFile = ({String path, int size, String sha256});

/// 一个量化档。[recommended] 是这个模型推荐用的那档。
typedef Quant = ({String label, ModelFile file, bool recommended});

/// 一个看图模型。[florence] 为真时是 Florence-2(ONNX,在程序里直接跑,不用 llama-server):
/// [quants] 只有一档(解码器),[extra] 是另外几个 ONNX 和分词器,[tasks] 是它认的指令。
/// 其余的是 GGUF,用 llama-server 跑,[mmproj] 是视觉组件。
typedef CaptionModel = ({
  String id,
  String series,
  String name,
  String params,
  String repo,
  String note,
  bool florence,
  List<Quant> quants,
  ModelFile? mmproj,
  List<ModelFile> extra,
  List<String> tasks,
});

const captionModels = <CaptionModel>[
  (
    id: 'gemma4-e2b',
    series: 'Gemma 4',
    name: 'Gemma 4 E2B',
    params: 'E2B',
    repo: 'unsloth/gemma-4-E2B-it-GGUF',
    note: '手机 / 核显级,约 2.3B 有效参数',
    florence: false,
    quants: [
      (
        label: 'UD-Q2_K_XL',
        file: (
          path: 'gemma-4-E2B-it-UD-Q2_K_XL.gguf',
          size: 2403614816,
          sha256: '2bfeb49803da8db274b3fbac3c1d471903be64d382c237c6f509ccaa9cc141a2',
        ),
        recommended: false,
      ),
      (
        label: 'Q4_K_M',
        file: (
          path: 'gemma-4-E2B-it-Q4_K_M.gguf',
          size: 3106738272,
          sha256: '740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8',
        ),
        recommended: true,
      ),
      (
        label: 'Q8_0',
        file: (
          path: 'gemma-4-E2B-it-Q8_0.gguf',
          size: 5048352864,
          sha256: '605d3c2647d7c58c1e4b5375ccb5702acf94c2611b4c8d4877812f8fdd32d053',
        ),
        recommended: false,
      ),
    ],
    mmproj: (
      path: 'mmproj-F16.gguf',
      size: 985654080,
      sha256:
          '140be8d7849741f88c50757d529b84373ee8e27052cc2236855b537f4a8215fa',
    ),
    extra: [],
    tasks: [],
  ),
  (
    id: 'gemma4-e4b',
    series: 'Gemma 4',
    name: 'Gemma 4 E4B',
    params: 'E4B',
    repo: 'unsloth/gemma-4-E4B-it-GGUF',
    note: '轻薄本级,约 4.5B 有效参数',
    florence: false,
    quants: [
      (
        label: 'UD-Q2_K_XL',
        file: (
          path: 'gemma-4-E4B-it-UD-Q2_K_XL.gguf',
          size: 3757419648,
          sha256: 'cc92186419be169e992a1df01978828a0d4cf3a5962379ff403c8d55f6faff78',
        ),
        recommended: false,
      ),
      (
        label: 'Q4_K_M',
        file: (
          path: 'gemma-4-E4B-it-Q4_K_M.gguf',
          size: 4977171584,
          sha256: '85a896a047553e842f25297ee5b031d64ff30147d9c4af17b1e4b394cd1fab87',
        ),
        recommended: true,
      ),
      (
        label: 'Q8_0',
        file: (
          path: 'gemma-4-E4B-it-Q8_0.gguf',
          size: 8192953472,
          sha256: 'f8854aa4480df62585a279e7ca0a881554fc18a41c59c4f62642d16a2ae47012',
        ),
        recommended: false,
      ),
    ],
    mmproj: (
      path: 'mmproj-F16.gguf',
      size: 990372672,
      sha256:
          'ddf46c21d7078e95338cfc22306b19b276a29a5ad089023449dd54d4b6170a51',
    ),
    extra: [],
    tasks: [],
  ),
  (
    id: 'gemma4-12b',
    series: 'Gemma 4',
    name: 'Gemma 4 12B',
    params: '12B',
    repo: 'unsloth/gemma-4-12b-it-GGUF',
    note: '统一多模态架构(图像 / 音频免编码器)',
    florence: false,
    quants: [
      (
        label: 'UD-Q2_K_XL',
        file: (
          path: 'gemma-4-12b-it-UD-Q2_K_XL.gguf',
          size: 4661419840,
          sha256: 'aa6e1ccf5cd1c5340c4786f0bda2478181327f14aba2359e51e455d02c90bff3',
        ),
        recommended: false,
      ),
      (
        label: 'Q4_K_M',
        file: (
          path: 'gemma-4-12b-it-Q4_K_M.gguf',
          size: 7121861440,
          sha256: '0a270ec9fe6b34f4a0d33992b6135117b484ebc4766ab76b51d4ae8c457e4c42',
        ),
        recommended: true,
      ),
      (
        label: 'Q8_0',
        file: (
          path: 'gemma-4-12b-it-Q8_0.gguf',
          size: 12669647680,
          sha256: 'f20e7ff1be28c283eeeb18fc895733791c56a5851d5cd3fe9691b7f7d12afa72',
        ),
        recommended: false,
      ),
    ],
    mmproj: (
      path: 'mmproj-F16.gguf',
      size: 175115840,
      sha256:
          '91f086971e56d7a7d8d39e271873fccdb49541bd259d6e02c401a4f1cb7a219e',
    ),
    extra: [],
    tasks: [],
  ),
  (
    id: 'gemma4-26b-a4b',
    series: 'Gemma 4',
    name: 'Gemma 4 26B A4B',
    params: '26B MoE',
    repo: 'unsloth/gemma-4-26B-A4B-it-GGUF',
    note: 'MoE:26B 总参 · 每 token 仅 3.8B 激活,内存换速度,CPU / 混合推理性价比高',
    florence: false,
    quants: [
      (
        label: 'UD-Q2_K_XL',
        file: (
          path: 'gemma-4-26B-A4B-it-UD-Q2_K_XL.gguf',
          size: 10546934240,
          sha256: '2a1d26dfe6ea00a467940a5728316af6edb366bbdba950d65b85d232392fb658',
        ),
        recommended: false,
      ),
      (
        label: 'UD-Q4_K_M',
        file: (
          path: 'gemma-4-26B-A4B-it-UD-Q4_K_M.gguf',
          size: 16947541728,
          sha256: 'f2c28b3dc4776931ac6f879e11f203dec637ea0f14267a86ec8f6165f63f293f',
        ),
        recommended: true,
      ),
      (
        label: 'Q8_0',
        file: (
          path: 'gemma-4-26B-A4B-it-Q8_0.gguf',
          size: 26859861728,
          sha256: '5f7cbd0f4564e84342fc34321a09acb54b1a3da9215124e5bf444baa6dda152c',
        ),
        recommended: false,
      ),
    ],
    mmproj: (
      path: 'mmproj-F16.gguf',
      size: 1193058784,
      sha256:
          '418a6d8723067cd712235facbbc5cba6c8fbbd413fc1292d2aace5a027d5a42f',
    ),
    extra: [],
    tasks: [],
  ),
  (
    id: 'gemma4-31b',
    series: 'Gemma 4',
    name: 'Gemma 4 31B',
    params: '31B',
    repo: 'unsloth/gemma-4-31B-it-GGUF',
    note: '稠密旗舰,质量最高,需要大显存 / 大内存',
    florence: false,
    quants: [
      (
        label: 'UD-Q2_K_XL',
        file: (
          path: 'gemma-4-31B-it-UD-Q2_K_XL.gguf',
          size: 11774991296,
          sha256: '3c0f374d3bc5d3d8c26adf27535354404f144922cecb8c57d7967647d56f17f3',
        ),
        recommended: false,
      ),
      (
        label: 'Q4_K_M',
        file: (
          path: 'gemma-4-31B-it-Q4_K_M.gguf',
          size: 18323733440,
          sha256: '38bd64c852c4b460434cc7162fa9bdcf242faf86502581a754cb72956bb17f84',
        ),
        recommended: true,
      ),
      (
        label: 'Q8_0',
        file: (
          path: 'gemma-4-31B-it-Q8_0.gguf',
          size: 32635677632,
          sha256: 'd5808e5874e660a85ab45b2da00c9e3b4a003621249a333772232d1a703e4d67',
        ),
        recommended: false,
      ),
    ],
    mmproj: (
      path: 'mmproj-F16.gguf',
      size: 1198957024,
      sha256:
          '6edcca228213c28d3567a35d22f849eea52d8360875093851959adf5d2f270eb',
    ),
    extra: [],
    tasks: [],
  ),
  (
    id: 'gemma4-e4b-heretic',
    series: 'Gemma 4 · Heretic',
    name: 'Gemma 4 E4B Heretic',
    params: 'E4B',
    repo: 'llmfan46/gemma-4-E4B-it-ultra-uncensored-heretic-GGUF',
    note: 'Heretic 去审查版 · 轻薄本级',
    florence: false,
    quants: [
      (
        label: 'Q4_K_M',
        file: (
          path: 'gemma-4-E4B-it-ultra-uncensored-heretic-Q4_K_M.gguf',
          size: 5335289696,
          sha256: 'f9dbbe3bdf396f65aec4e801516a1b868a510d96225417a8aa06763e3c5b97dc',
        ),
        recommended: true,
      ),
      (
        label: 'Q8_0',
        file: (
          path: 'gemma-4-E4B-it-ultra-uncensored-heretic-Q8_0.gguf',
          size: 8031240032,
          sha256: 'c1543610bcceeba8f51bd7cf38f373d2a002265f8873149aecae8a200b8fe4ba',
        ),
        recommended: false,
      ),
    ],
    mmproj: (
      path: 'gemma-4-E4B-it-mmproj-BF16.gguf',
      size: 991552000,
      sha256:
          'ffa64aebf7144bbadd5a1e143b77794d88e76a81cc0168d91de0770eb49e88e0',
    ),
    extra: [],
    tasks: [],
  ),
  (
    id: 'gemma4-12b-heretic',
    series: 'Gemma 4 · Heretic',
    name: 'Gemma 4 12B Heretic',
    params: '12B',
    repo: 'culturerevolt/gemma-4-12b-heretic-abliterated-GGUF',
    note: 'Heretic 去审查 + abliterated 版',
    florence: false,
    quants: [
      (
        label: 'IQ3_XS',
        file: (
          path: 'gemma-4-12b-heretic-IQ3_XS.gguf',
          size: 5272393056,
          sha256: 'e3b989172aeca98f32200c8031c603cd7191d8d487acd3cfde59c26ba4d4f4b7',
        ),
        recommended: false,
      ),
      (
        label: 'Q4_K_M',
        file: (
          path: 'gemma-4-12b-heretic-Q4_K_M.gguf',
          size: 7381382496,
          sha256: '6c4067ea0210d2367b2dbdd460d2dd86032a9b6e8dcbe03b83a3ea0a0a16dbee',
        ),
        recommended: true,
      ),
      (
        label: 'Q8_0',
        file: (
          path: 'gemma-4-12b-heretic-abliterated-Q8_0.gguf',
          size: 12669645440,
          sha256: 'e4734aeb71209e9595eaac1b46b6370f4329cad4515ab449a788cb3b04745dec',
        ),
        recommended: false,
      ),
    ],
    mmproj: (
      path: 'gemma-4-12b-heretic-mmproj-f16.gguf',
      size: 175115840,
      sha256:
          '2e269f906eb15169ee9ce880ea649bd6d42d4964c21f8ede10d0d0efc738bcbb',
    ),
    extra: [],
    tasks: [],
  ),
  (
    id: 'gemma4-31b-heretic',
    series: 'Gemma 4 · Heretic',
    name: 'Gemma 4 31B Heretic',
    params: '31B',
    repo: 'llmfan46/gemma-4-31B-it-uncensored-heretic-GGUF',
    note: 'Heretic 去审查版稠密旗舰',
    florence: false,
    quants: [
      (
        label: 'Q3_K_M',
        file: (
          path: 'gemma-4-31B-it-uncensored-heretic-Q3_K_M.gguf',
          size: 15287108736,
          sha256: 'c0e2810df3603c8bcd103f9b7bbe0fa76c1422df8724c2989d6091641f5a4a10',
        ),
        recommended: false,
      ),
      (
        label: 'Q4_K_M',
        file: (
          path: 'gemma-4-31B-it-uncensored-heretic-Q4_K_M.gguf',
          size: 18687063168,
          sha256: '7c65a35e7c4e53cba6c5e02cc9eeb850eb4251f4d9ad120c2caa6de23c5a6395',
        ),
        recommended: true,
      ),
      (
        label: 'Q8_0',
        file: (
          path: 'gemma-4-31B-it-uncensored-heretic-Q8_0.gguf',
          size: 32635675776,
          sha256: 'fc1096ef2a43023469beecaa5a7fa3ba804d3f1684ade80f8f083e7e27a1028e',
        ),
        recommended: false,
      ),
    ],
    mmproj: (
      path: 'gemma-4-31B-it-mmproj-BF16.gguf',
      size: 1200726208,
      sha256:
          '21487ff26d08f7ddd1d654d3bbfc1ae1020aab3119f5bf654742ce4697732e4e',
    ),
    extra: [],
    tasks: [],
  ),
  (
    id: 'toriigate-0.5',
    series: 'ToriiGate',
    name: 'ToriiGate 0.5',
    params: '4B',
    repo: 'DraconicDragon/ToriiGate-0.5-GGUF',
    note: '基于 Qwen3.5-4B · 动漫 / 插画标注特化(原仓库 Minthy/ToriiGate-0.5)',
    florence: false,
    quants: [
      (
        label: 'Q4_K_M',
        file: (
          path: 'ToriiGate-0.5-Q4_K_M.gguf',
          size: 3066382176,
          sha256: '1dd18497b1a1ee19e5ca63a58efb4614bfd24abf80ee7fd796bbbe3bc1e20cef',
        ),
        recommended: true,
      ),
      (
        label: 'Q6_K',
        file: (
          path: 'ToriiGate-0.5-Q6_K.gguf',
          size: 3985524576,
          sha256: '2452c180427a127fe536e03c00cf5249f38c1378ae4d17a29e1a9f2371b5a852',
        ),
        recommended: false,
      ),
      (
        label: 'Q8_0',
        file: (
          path: 'ToriiGate-0.5-Q8_0.gguf',
          size: 5157830496,
          sha256: '2b21dce659e9ba92ebf481468b7cea131e614f162fc43ddb8c834ffaf4364020',
        ),
        recommended: false,
      ),
    ],
    mmproj: (
      path: 'ToriiGate-0.5-fp16.mmproj.gguf',
      size: 672423360,
      sha256:
          'e0470d4bff4e932ecf3c7bf3b937d51301722c5d17c43f7ad9dfc73b65808b9c',
    ),
    extra: [],
    tasks: [],
  ),
  (
    id: 'joycaption-beta-one',
    series: 'JoyCaption',
    name: 'JoyCaption Beta One',
    params: '8B',
    repo: 'concedo/llama-joycaption-beta-one-hf-llava-mmproj-gguf',
    note: '基于 Llama-3.1-8B LLaVA · 写实图片描述',
    florence: false,
    quants: [
      (
        label: 'Q4_K',
        file: (
          path: 'Llama-Joycaption-Beta-One-Hf-Llava-Q4_K.gguf',
          size: 4920735936,
          sha256: 'e8ae55dd07e61d541ab741d6ed63e7810192cea65d7ef8cda69b2a99fb06dc15',
        ),
        recommended: true,
      ),
      (
        label: 'Q8_0',
        file: (
          path: 'Llama-Joycaption-Beta-One-Hf-Llava-Q8_0.gguf',
          size: 8540772544,
          sha256: '914fccbc28d0bdf87bab2937f58707bbc33556021664cd16a9666607d4058b99',
        ),
        recommended: false,
      ),
    ],
    mmproj: (
      path: 'llama-joycaption-beta-one-llava-mmproj-model-f16.gguf',
      size: 877771808,
      sha256:
          '94002cb5c354c7c9e538e64f37d593db9eceeca2e94573bae6cd3b2bd8bb1952',
    ),
    extra: [],
    tasks: [],
  ),
  (
    id: 'florence2-promptgen-v2',
    series: 'Florence-2',
    name: 'Florence-2 PromptGen v2.0',
    params: '0.23B',
    repo: 'laub/Florence-2-large-PromptGen-v2.0-onnx',
    note: '打标特化 · 指令驱动(标签 / 标题 / 构图分析),免 llama-server;社区 ONNX 导出为 base 架构(仓库名标 large,实为 0.23B;large 版暂无可用 ONNX)',
    florence: true,
    quants: [
      (
        label: 'ONNX',
        file: (
          path: 'onnx/decoder_model_merged.onnx',
          size: 388209807,
          sha256: '4bd1dce482d3df8f6c592b248b0de8e62780d2ad5a3f3ae9b3d42b321b83a678',
        ),
        recommended: true,
      ),
    ],
    mmproj: null,
    extra: [
      (
        path: 'onnx/vision_encoder.onnx',
        size: 366564017,
        sha256:
            '0894e2fd104d64e31d0fc22dd2dfba498f0455bcb5416534972777943c38ac17',
      ),
      (
        path: 'onnx/embed_tokens.onnx',
        size: 157560044,
        sha256:
            'b95f49725068d0addbb3c0522d842cb4d9e968106563583deccae3a462378ee1',
      ),
      (
        path: 'onnx/encoder_model.onnx',
        size: 173380907,
        sha256:
            '3243b162d86802e572969581362b3efeba8329dbb8da1e2ff4fb053913e6c2df',
      ),
      (
        path: 'tokenizer.json',
        size: 2297961,
        sha256:
            'd69dcdb2323e124ac4f800cb9863ddccea0d7bb11e16125e8df3bd60f2f8aeac',
      ),
    ],
    tasks: [
      '<GENERATE_TAGS>',
      '<CAPTION>',
      '<DETAILED_CAPTION>',
      '<MORE_DETAILED_CAPTION>',
      '<ANALYZE>',
      '<MIXED_CAPTION>',
      '<MIXED_CAPTION_PLUS>',
    ],
  ),
  (
    id: 'florence2-base-ft',
    series: 'Florence-2',
    name: 'Florence-2 base-ft(官方)',
    params: '0.23B',
    repo: 'onnx-community/Florence-2-base-ft',
    note: '微软官方 base 任务微调版 · 标准标题三档指令',
    florence: true,
    quants: [
      (
        label: 'ONNX',
        file: (
          path: 'onnx/decoder_model_merged.onnx',
          size: 388421753,
          sha256: '5207affad8815294233b8679ee9ecb614906f819a1890d95a01b9ca68c392a79',
        ),
        recommended: true,
      ),
    ],
    mmproj: null,
    extra: [
      (
        path: 'onnx/vision_encoder.onnx',
        size: 366549825,
        sha256:
            'd67258cdfdebfa21285dad9e7bd4bd99725236d0aaef9e474a1b24a6ec471351',
      ),
      (
        path: 'onnx/embed_tokens.onnx',
        size: 157560044,
        sha256:
            '90cae3deb6406938c676a35b5246db02b478c9cc8cf93508361be80c05babf95',
      ),
      (
        path: 'onnx/encoder_model.onnx',
        size: 173380723,
        sha256:
            'cb0bccc232c64290397f5e1235eb3e1fa6ccf8c5afed9216480ee4eed80737fc',
      ),
      (
        path: 'tokenizer.json',
        size: 2297961,
        sha256:
            'd69dcdb2323e124ac4f800cb9863ddccea0d7bb11e16125e8df3bd60f2f8aeac',
      ),
    ],
    tasks: ['<MORE_DETAILED_CAPTION>', '<DETAILED_CAPTION>', '<CAPTION>'],
  ),
  (
    id: 'florence2-large-ft',
    series: 'Florence-2',
    name: 'Florence-2 large-ft(官方)',
    params: '0.77B',
    repo: 'onnx-community/Florence-2-large-ft',
    note: '微软官方 large 任务微调版 · 标准标题三档指令',
    florence: true,
    quants: [
      (
        label: 'ONNX',
        file: (
          path: 'onnx/decoder_model_merged.onnx',
          size: 1021996421,
          sha256: 'a35016ed99f4260f584bdef0602617cf344dafe8d72631d2a7e5933f105f4ea6',
        ),
        recommended: true,
      ),
    ],
    mmproj: null,
    extra: [
      (
        path: 'onnx/vision_encoder.onnx',
        size: 1453500335,
        sha256:
            'cbe2b9e3bfd5f00f9c135c3c48e4e8a2ad2b35651309d213dbf0803cc862d491',
      ),
      (
        path: 'onnx/embed_tokens.onnx',
        size: 210080043,
        sha256:
            '8497716365d7636307b334a665b0fe3482c9dfc3cc3e31c1d110c25ec183e31d',
      ),
      (
        path: 'onnx/encoder_model.onnx',
        size: 609049107,
        sha256:
            'f4622b5203e353c0e660f8d2ccd50a1179a092cd2408b208bc9539f1572a321d',
      ),
      (
        path: 'tokenizer.json',
        size: 2297961,
        sha256:
            'd69dcdb2323e124ac4f800cb9863ddccea0d7bb11e16125e8df3bd60f2f8aeac',
      ),
    ],
    tasks: ['<MORE_DETAILED_CAPTION>', '<DETAILED_CAPTION>', '<CAPTION>'],
  ),
  (
    id: 'florence2-base',
    series: 'Florence-2',
    name: 'Florence-2 base(官方)',
    params: '0.23B',
    repo: 'onnx-community/Florence-2-base',
    note: '微软官方 base 预训练版(未任务微调,建议优先 -ft)',
    florence: true,
    quants: [
      (
        label: 'ONNX',
        file: (
          path: 'onnx/decoder_model_merged.onnx',
          size: 388421910,
          sha256: '6d6e1266d7f94f5d4ec9cc07d9c1f7b3e47049c9b0de7bbe82a91e62dfd152af',
        ),
        recommended: true,
      ),
    ],
    mmproj: null,
    extra: [
      (
        path: 'onnx/vision_encoder.onnx',
        size: 366591558,
        sha256:
            '2c7464fce495ea43b415b48afe7dbe84a9ebbe0cfe3c31fdd81c6dd66b39ff75',
      ),
      (
        path: 'onnx/embed_tokens.onnx',
        size: 157560107,
        sha256:
            'fec0fd20276af861afb6a23a11544bf1378c05e2a41001b610cc281e244c4b20',
      ),
      (
        path: 'onnx/encoder_model.onnx',
        size: 173380723,
        sha256:
            'b155b5a0e56a4244c62060751bb1b70dfe481015d0dbfa6d19b1912d9e58da0d',
      ),
      (
        path: 'tokenizer.json',
        size: 2297961,
        sha256:
            'd69dcdb2323e124ac4f800cb9863ddccea0d7bb11e16125e8df3bd60f2f8aeac',
      ),
    ],
    tasks: ['<MORE_DETAILED_CAPTION>', '<DETAILED_CAPTION>', '<CAPTION>'],
  ),
  (
    id: 'florence2-large',
    series: 'Florence-2',
    name: 'Florence-2 large(官方)',
    params: '0.77B',
    repo: 'onnx-community/Florence-2-large',
    note: '微软官方 large 预训练版 · BAI_JSON LoRA 的推荐载体(直系底座)',
    florence: true,
    quants: [
      (
        label: 'ONNX',
        file: (
          path: 'onnx/decoder_model_merged.onnx',
          size: 1021996421,
          sha256: 'b8cc87fea29465237fc9980ee9cf4ef5c6a3e197d78ae6fd1e0b31c20bf7fd80',
        ),
        recommended: true,
      ),
    ],
    mmproj: null,
    extra: [
      (
        path: 'onnx/vision_encoder.onnx',
        size: 1453500335,
        sha256:
            '3579b2a9fe0e73d80a6e6152c610c80fed3739bc9e386145740ac41a0ac0dc05',
      ),
      (
        path: 'onnx/embed_tokens.onnx',
        size: 210080043,
        sha256:
            'af0a7ec8918e556c4f3b7931271b8cf882db2024e2b777955daa053ee6a881b3',
      ),
      (
        path: 'onnx/encoder_model.onnx',
        size: 609049107,
        sha256:
            '3046c1c8abee3c1d5ed667db738035a4abbe2793c5298683a8ccf1d6db5f4170',
      ),
      (
        path: 'tokenizer.json',
        size: 2297961,
        sha256:
            'd69dcdb2323e124ac4f800cb9863ddccea0d7bb11e16125e8df3bd60f2f8aeac',
      ),
    ],
    tasks: ['<MORE_DETAILED_CAPTION>', '<DETAILED_CAPTION>', '<CAPTION>'],
  ),
];
