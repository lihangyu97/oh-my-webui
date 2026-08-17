# Changelog

## [1.0.3] - 2026-08-17

### 功能

- **命令按工作目录分组**：侧栏按 `workingDirectory` 完整路径精确分组，组名显示最后两级目录（`/a/b/c/d` → `c/d`），未设置显示 `home`，组头 tooltip 显示完整路径
- **组内拖拽排序**：组顺序 = 组内首项在数组中的位置，零新增字段；跨组拖拽自然回弹（不支持跨组）
- **折叠动画**：改用系统原生 `Section(isExpanded:)`，展开/收起带系统过渡动画
- **工作目录只读化**：编辑表单改为只读展示 + Finder 选择/清除，禁止手输（杜绝相对路径、`~` 未展开、尾斜杠等脏数据）
- **运行中命令保护**：右键"编辑"运行中灰显（改的是下次启动配置）；右键"删除"运行中弹二次确认（删除 = 终止进程，防误触）

### 修复

- **崩溃**：移除删除命令时的 `WKWebsiteDataStore.remove(forIdentifier:)`——实测 WebKit 未初始化时调用必崩（崩溃在 WebKit 内部 RunLoop 的 `os_unfair_lock`），数据残留无害，不再清理
- **右键菜单禁用状态不实时刷新**：contextMenu 移入行视图（`@ObservedObject` 观察 runner），运行状态变化实时重建菜单，编辑禁用立即生效
- **单级目录组名错误**（`//a` 应为 `a`）：`NSString.lastPathComponent` 对根路径返回 `"/"` 而非空串的判断修正（由单元测试抓出）

### 工程优化（重构 + 测试 + 性能）

- **代码组织**
  - `AppModel` 按职责拆为四个文件：核心状态 + `AppModel+Runtime`（进程启停）+ `AppModel+Commands`（CRUD/分组）+ `AppModel+Persistence`（JSON 持久化）
  - `CommandSection` 归位到 `Models/`；新增 `Models/AppConstants.swift`（窗口 id、AppStorage key、bundle id 兜底集中管理，替换散落字符串）
  - `WebViewWindow.swift` 拆为三个文件：窗口壳 / `BrowserWebView`（WKWebView 包装）/ `WindowChromeConfigurator`（窗口外观）
  - 新增 `easy-webuiTests` 单元测试 target 与共享 scheme

- **性能**
  - 日志解析移出主线程：新增 `OutputParser`（nonisolated，串行队列切行/去 ANSI），主线程只更新 `@Published`；URL 提取提成可测纯函数 `WebCLIRunner.firstURL`
  - 正则预编译为 `static let`（URL / ANSI），不再每行编译
  - `stop()` 的延时闭包改为捕获 `Process` 而非 `self`：删除命令后不再用强引用延长 runner 生命周期，进程清理仍保证执行
  - 状态涟漪动画只作用于选中行（`StatusDot.animated`），非选中运行行静态圆点

- **健壮性**
  - `commands.json` 读写失败用 `os_log` 记录（不再静默吞掉）

- **测试**（`easy-webuiTests`，19 个用例）
  - `CommandSection`：组名两级/单级/根/尾斜杠/nil 边界
  - 分组：有序分组、组顺序、空列表
  - `OutputParser`：跨块切行、去 ANSI、URL 不被拦腰切断、空块、未收尾行
  - `WebCLIRunner.firstURL`：HTTP/HTTPS/非 HTTP/多个 URL/ANSI 邻接

- **CI**：`build-dmg.yml` 增加单元测试步骤

## 历史

见 git 提交历史。
