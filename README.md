# AFM輸入法 (afm-ime)

同一個 macOS App 提供 **AFM拼音**及新增的 **AFM速成**兩個系統輸入來源，共用設定中心及 Liquid Glass 框架。拼音保留原有引擎、完整詞庫及模型功能；繁體速成使用從 Windows 提取的原生字碼及聯想資料，預設固定次序，完整字集、個人學習及 AI 重排均可獨立手動開啟。

**純 Swift、無第三方依賴，最低部署版本 macOS 26。**可用 Xcode 27 或 Command Line Tools 27 構建；拼音水滴的 Metal 折射效果需要 Xcode Metal 工具鏈。AI 可使用本機 Apple Foundation Models；macOS 27 或以上亦可手動啟用已配置的雲端模型。macOS 26 的執行期相容性仍待實機驗收。

![平台](https://img.shields.io/badge/macOS-26%2B%20(Apple%20Intelligence)-blue) ![构建](https://img.shields.io/badge/Swift-6.4%20·%20Xcode%2027-orange)

已發佈的可用基礎版為 **2026.10.15（macOS 27+）**：[下載安裝包及查看版本說明](https://github.com/makcheunghei/afm-ime/releases/tag/v2026.10.15)。安裝包已包含拼音及速成詞庫；由原始碼構建則須按下文準備詞庫資料。

## 繁體速成

- **英文優先中英混輸**：行內保留原文及大小寫；1–2 字母顯示速成候選，數字 `1–9` 或點選輸出中文（例如 `ma1` →「百」）。第三個字母起收起中文候選，繼續輸入 `makcheunghei` 會完整保留。單碼空白直接輸出目前中文字，雙碼空白循環翻頁（只有一頁或無候選時不確認）；英文用 Enter 確認原文。第三字母起的英文空白保留在組字內，Enter 一次確認整段；失焦及標點亦不自動選中文。Backspace 逐字刪除。
- **單欄候選及鍵盤翻頁**：每頁最多 9 字，頂部只顯示目前頁／總頁數；左右方向鍵／Page Down／Page Up 翻頁，上下方向鍵移動高亮，數字按當頁位置選字。Tab 交回應用程式。英文組字期間的標點及數字保留半角；`0` 或沒有對應候選的數字保留為原文。短英文加數字若與選字衝突（例如 `ma1`），可輕點 Shift 切至英文模式輸入。
- **原生聯想**：選字後顯示續文，以 Shift＋1–9 選取；聯想提交後關窗，不再自動連鎖開窗。
- **固定字序為預設**：完整字集及速成個人學習各有獨立開關，預設關閉；學習資料與拼音分開，關閉時不寫入速成學習資料。
- **速成 AI 預設關閉**：開啟後保留第一候選，推薦放第二位並標記 ✦；導航或翻頁後鎖定本次次序。雲端有另一個獨立開關，未開啟時只使用本機模型。
- **已核對的 Windows 樣本**：`aa` 的 18 個候選及「你、晶、香、港、好、暑」六組聯想。全碼排序、擴展字篩選及其他字詞仍需逐步對照，現階段不保證所有字碼與 Windows 完全一致。資料來源、數量及驗證範圍見 [速成說明](docs/quick.md)。

候選面板使用系統原生標準 Liquid Glass 材質，不另設透明度或色調覆蓋；macOS 27 自動跟隨系統透明度及輔助使用設定，macOS 26 使用預設效果。

## 拼音及共用功能

- **词典引擎**:多源词库 **698.6 万条**(含简拼派生键,原始词条 ~350 万),编译为二进制 `dict.bin`,mmap 零拷贝加载(<1ms),热循环查询 ~0.2ms
  - rime-ice 雾凇拼音(tencent 98w + base 55w + ext 34w + 8105 单字)
  - 萌娘百科(mw2fcitx 月更)12.9w / 中文维基 167w / Minecraft Wiki 1.1w / 蔚蓝档案 / THUOCL 9.4w / ali-words 黑话 / 自维护梗合集(无拼音源编译期自动注音)/ CLDR emoji / 化学式·希腊字母
- **用户词库**:上过屏的词按拼音键记忆,同键输入**最高优先档直出、越打越顺**(跨重启);词组自动学习(分段组句合成词组,修词典外短语冷启动);简拼、半截音节宽松匹配(mebengz→没绷住、nh→女孩);**内置作者词库种子**(开箱即有一份调好的个人词库,删过的不随版本升级复活),设置中心可**导入用户词 JSON**(同格式互换)
- **大模型增强**(重排/整句/翻译三入口共用;**云端→端侧→纯词典逐级静默回退,永不阻塞打字**):
  - *候选重排*:打字停顿 ~0.4s 后,模型根据上文把最合适的候选提到第 2 位(✦ 标记,不顶掉首选、防突然换词打错),到达后无感刷新
  - *整句预测*:长拼音词典覆盖不住时,光标处先显示占位,模型输出整句候选
  - *云端模型(可选)*:经 FoundationModels 官方 Provider 协议接入,与端侧同一套提示词(重排/整句/翻译×2 四段可整段覆盖,草稿-应用模式);设置中心「模型」页配置——提供商预设 9 种(OpenAI/Anthropic/DeepSeek/Kimi/智谱/通义/豆包/Ollama/自定义)、OpenAI 兼容 vs Anthropic 双线格式、Base URL/API Key/模型名、测试连接
- **拼音切分与模糊音**:音节树最多 12 路切分枚举,尾部不完整音节实时匹配;模糊拼音 zh/z、ch/c、sh/s、an/ang、en/eng、in/ing(含 ian↔iang、uan↔uang)双向模糊,精确拼音候选永远优先;简拼(awsl→阿伟死了)与全拼混输(n+hao→你好);渐进前缀兜底(超长句出「你是X」);词格 DP 整句组词
- **组词中 Shift+字母 = 大写英文字尾**:GDP 这类混排直接打,随候选一并上屏
- **伴随面板**(液态玻璃,浮在候选条下方/上方,无候选条时屏幕右上角):
  - *剪贴板历史* `⌃V`:免激活不打断组词,复制过的文本自动收录(50 条/跨重启),点击或数字键插回光标
  - *内联翻译* `⌃F`:组词中把当前高亮候选的译文单行显示在候选框,空格上屏译文;独立翻译页在设置中心(中↔英方向自动,结果可复制)
- **液态玻璃候选窗**:NSPanel + NSGlassEffectView(macOS 27 真·Liquid Glass,亮暗自适应),跟随光标;选中态 = 透明液态玻璃水滴(Metal 折射镜头),按住可左右拖动、松手吸附最近候选上屏;候选条恒显前 8 个,`↓` 展开滚动网格
- **控制中心**(嵌在输入法 bundle 内,`⌃S` 或输入菜单「设置…」打开):七区——**安装**(一键安装并启用/更新/卸载)、**词库**(698 万条分页浏览+拼音搜索)、**用户词**(词/拼音键/次数/乘数管理+导入)、**翻译**(端侧 FM 中↔英互译)、**模型**(云端配置+提示词覆盖)、**测试**(实验交互开关)、**设置**(模糊拼音/全角标点/FM 增强/词频学习/候选条字号/**快捷键自定义**),写 IME 域即时生效

## 截图

**候选条与伴随面板** —— `⌃V` 剪贴板历史 / `⌃F` 翻译浮窗与候选条并存,不打断组词:

![候选条与伴随面板](docs/screenshots/companion-panels.png)

**剪贴板历史** —— 复制过的文本自动收录,点击或数字键插回光标:

![剪贴板历史](docs/screenshots/clipboard-panel.png)

**整句预测** —— 长拼音词典覆盖不住时,模型输出的 ✦ 整句候选插在第 2 位,空格直接上屏:

![整句预测](docs/screenshots/fm-sentence.png)

**设置中心「模型」页** —— 云端模型配置(提供商 / 接口格式 / Base URL / API Key / 模型名 / 测试连接)与提示词覆盖:

![设置中心模型页](docs/screenshots/settings-model.png)

## 构建 / 安装

使用 macOS 27 SDK，部署目標為 macOS 26。Xcode 27 是主構建路徑；沒有 Xcode 時自動使用 Command Line Tools，保留 Liquid Glass 候選窗，拼音水滴沒有 Metal 折射。

```sh
# Metal 工具链组件(~839MB,一次;DEVELOPER_DIR 指向你的 Xcode 安装)
DEVELOPER_DIR=/Applications/Xcode-beta.app xcodebuild -downloadComponent metalToolchain

scripts/fetch_pinyin_dict.sh # 缺少 dict.bin 時，從固定上游發行版提取完整詞庫並核對 SHA-256
python3 scripts/build_quick.py # 從 quickime/ 的原生 Windows 檔案生成 Data/quick.json
scripts/package.sh          # 打包同時包含拼音及速成的 App
scripts/test.sh             # Swift Testing 行為測試（包含 CLT framework 路徑處理）
"build/AFM輸入法.app/Contents/MacOS/AFMInput" --check-quick # 打包後的資料／按鍵整合檢查
# 有完整拼音源時，可用 scripts/build_dict.sh 重新編譯 dict.bin
```

產物 `build/AFM輸入法.app` 包含輸入法引擎及內嵌設定中心（`Contents/PlugIns/AFMSettings.app`），頂層只有一個 App。速成原始資料及生成的詞庫不納入 Git；本地所需檔案與自訂來源參數見 [速成說明](docs/quick.md)。

- **首次安裝**：`open build/AFM輸入法.app` → 設定中心「安裝並啟用」，或執行 `scripts/install.sh`，預設安裝到 `~/Library/Input Methods/AFM輸入法.app`。來源由 macOS 收錄後，在系統設定自行加入所需模式。首次未列出時，系統可能需要登出再登入；`scripts/post-login-check.sh` 只檢查，不改動來源。
- **切換來源**：macOS 輸入來源列表分別提供「AFM拼音」及「AFM速成」。設定中心「設定」頁有獨立的「繁體速成」選項。
- **安裝包**：`scripts/make_pkg.sh` 產生 `build/AFM輸入法-<版本>.pkg`，安裝到系統級 `/Library/Input Methods`，由系統要求管理員授權。App 簽署依序優先使用 Developer ID Application、Apple Development、本機開發證書；沒有證書才使用 ad-hoc。安裝包只會使用同一 Team 的 Developer ID Installer；缺少時會明確產生未簽署安裝包。簽署與 Apple 公證分開處理，腳本不會自動提交公證。
- **日常更新**：重新執行 package.sh，再從新包的設定中心使用「更新輸入法」；安裝包及 `scripts/install.sh` 只更新 App，不註冊、啟用或補回已移除的模式，亦不覆寫系統的啟用清單。

可用 `AFM_SIGN_IDENTITY`（證書名稱或 SHA-1）及 `AFM_SIGN_TEAM` 明確選擇 App 簽署身份，`AFM_INSTALLER_IDENTITY` 選擇安裝包身份。同級證書分屬多個 Team 時會停止要求指定；簽署失敗亦會停止，不會靜默降級。選擇器可用 `bash scripts/test_signing_identities.sh` 及 `zsh scripts/test_signing_identities.sh` 測試。

用 `"build/AFM輸入法.app/Contents/MacOS/AFMInput" --status` 可唯讀查閱兩個模式的註冊及啟用狀態；`--check-quick` 不初始化 IMKServer，也不修改系統輸入來源。

拼音及速成均不宣告為自動啟用或必須保留的主要模式，可以在系統設定獨立加入及移除。明確使用命令行註冊時，同一份安裝檔只遞交一次；更新檔案後可補註冊，不反覆遞交。系統 API 的實例數可能與設定畫面不同，實際輸入來源請以「系統設定 → 鍵盤 → 輸入方式 → 編輯」核對。封包製作及上游詞庫提取均使用不索引的暫存目錄，完成或失敗後自動清理。

首次安裝後如果新增列表及輸入法選單仍沒有 AFM，須登出再登入，讓 macOS 完成登入掃描；API 顯示已註冊或已設定啟用，不能代替真實選單及切換驗證。輸入法引擎是背景程式；已啟動時再次打開 App 會開啟設定中心，也可直接開啟 App 內的 `Contents/PlugIns/AFMSettings.app`。

## 使用

- **AFM速成**：輸入 `makcheunghei` 後按 Enter，應得到 `makcheunghei`；`I`、`am`、`of`、`AI` 同樣以 Enter 輸出英文。`o`、空白輸出「人」；`of`、空白循環翻頁，單頁不確認。`ma1` 輸出「百」；`of`、右方向鍵測試翻頁，再按數字選字；`of`、`2`、Shift＋`1` 輸出「你們」。聯想窗空白插入空格並關窗，普通數字不選聯想。Backspace 逐字刪除，Esc 取消組字或關閉聯想。
- 以下為原有 **AFM拼音**及共用快捷鍵：
- `Ctrl+Space` 或菜单栏切换到 AFM拼音;**轻点 `Shift` 中英切换**(系统级监听、全部应用生效,跨重启记忆;英文模式无候选框、标点半角直通)
- 中文模式:打拼音 → 数字 `1-8` 选词 / `空格` 上屏高亮候选 / `回车` 上屏拼音原文(网格展开时回车=空格上屏选中);选中候选为透明水滴,**按住左右拖动,松手吸附上屏**(设置中心「测试」可开「固定透镜」模式:水滴钉在原地,整条候选栏从它下面滑过)
- `←→` 移动高亮(越过第 8 个自动展开网格),`↓` 展开候选网格(8 列,滚轮/滚动条滚动、边缘跟随,移回首行或顶行 `↑` 收起),`=`/`-` 翻页,候选条 `▾`/`▴` 展开收起,`Esc` 取消组词;网格内数字键按水滴所在行的 1-8 选词
- `⌃V` 剪贴板历史 / `⌃F` 内联翻译 / `⌃S` 设置中心(三键均可在设置中心自定义,修饰键固定 ⌃);`⌃;` 打开系统「显示表情与符号」;emoji 直接拼音打(`xiaolian`→😀,词库来自 CLDR 中文注解)
- 组词中按住 `Shift` 敲字母 = 大写英文字尾(如 GDP),随候选一并上屏
- 中文标点自动全角：，。；：？！（）【】「」《》、·～,以及 `Shift+-`→——、`Shift+6`→……、`Shift+4`→￥;引号 `'`→‘’、`Shift+'`→“”,均成对交替(`-`/`=`/空格/数字保持半角)
- FM/云端整句:长拼音停顿后出现 ✦ 候选,`空格` 直接上屏

## Debug

```sh
scripts/debug.sh        # 重启输入法,实时跟踪 /tmp/afm-ime.log
scripts/debug.sh --stop # 关闭 debug(标志文件 /tmp/afm-ime-debug)
```

## 结构

```
Sources/
├── IMECore/        # 引擎核心:词库(DictStore mmap)、拼音切分、候选引擎、FM 层(FMReranker 统一出口:
│                   #   云端 CloudProvider → 端侧 FoundationModels → 纯词典)、用户词频与用户词库、
│                   #   模型偏好(ModelPrefs/CloudProvider)、TIS 安装器、debug 日志、
│                   #   速成資料(QuickDictionary)、查表／學習(QuickEngine)、按鍵狀態機(QuickSession)
├── AFMInput/       # 输入法主体(IMKServer/InputController/液态玻璃候选窗+水滴/⌃V·⌃F 伴随面板/
│                   #   Shift 中英监听)+ 安装 CLI
├── AFMApp/         # 设置中心(六区;打包为引擎 bundle 内 PlugIns/AFMSettings.app 独立进程)
├── DictCompiler/   # 多源词库 → dict.bin 编译器(rime yaml/撇号拼音/词频 TSV/源码提取/markdown)
├── DictBench/      # 词库加载/查询基准(含各外部词库源回归查询)
└── *Bench/         # FMStructBench / CloudModelBench / ProviderBench(FM 框架与云端协议实测)
vendor/             # 词库源 + 参考实现(rime-ice、squirrel、fcitx5-macos、AndroidLiquidGlass 等)
Experiments/        # FM 框架测绘、梗合集词库等实验材料
scripts/            # package / build_dict / install / uninstall / debug 等全部脚本
Data/dict.bin       # 拼音詞庫（Git 忽略，可從固定上游封包取回或 build_dict.sh 重新生成）
Data/quick.json     # 速成詞庫／聯想（Git 忽略，build_quick.py 生成）
Tests/IMECoreTests/ # 速成引擎、狀態機、AI 鎖定、學習開關及 Unicode 行為測試
```

## 性能(本机 macOS 27 / M 系列)

| 场景 | 耗时 |
|---|---|
| 词库加载(mmap) | 0.2–1ms |
| 单次候选查询 | 0.1–4ms |
| FM 重排(暖) | ~350ms(异步,不阻塞打字) |
| FM 整句(暖) | ~350ms(占位等待) |

云端模型延迟取决于网络与提供商(请求 15s 超时,失败自动回落端侧,再回落纯词典)。
