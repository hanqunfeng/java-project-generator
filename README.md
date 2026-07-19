# java-project-generator

用于快速生成 Spring Boot 项目的脚本工具，支持：
- 单模块项目（`jar` / `war`，通过 Spring Initializr 拉取）
- 多模块 Maven 项目（`pom`，本地生成父子模块结构）
- 多模块 Gradle 项目（`pom` 模式，本地生成父子模块结构）
- 已有 Maven/Gradle 多模块项目追加子模块（含嵌套路径）

## 目录结构

```text
java-project-generator/
├── springboot         # 入口脚本：参数解析、校验、调度
├── deps-cache/        # 依赖缓存与网页渲染产物
│   ├── boot-<ver>.md
│   └── boot-web.html
├── assets/            # 静态资源（如网页样式）
│   └── web_style.css
├── completions/       # shell 自动补全脚本
│   ├── springboot.bash
│   └── _springboot
├── scripts/
│   └── check.sh       # 本地统一检查入口（shellcheck + bats）
└── lib/
    ├── arg-common.sh  # 参数处理公共逻辑（CSV 规范化/迭代）
    ├── deps.sh        # 依赖/Initializr 交互（缓存、声明提取、deps 子命令实现）
    ├── single.sh      # 单模块生成逻辑（jar/war）
    ├── multi-maven.sh # Maven 多模块生成逻辑
    ├── multi-gradle.sh # Gradle 多模块生成逻辑
    ├── nested-common.sh # 嵌套模块公共逻辑
    ├── module-template-common.sh # 模块骨架模板公共逻辑
    └── project-common.sh # 项目级公共逻辑（如 .gitignore）
```

## 工作原理

- `springboot` 负责统一解析参数、校验参数、打印配置
- 支持 `INITIALIZR_BASE_URL` 覆盖默认 `https://start.spring.io`
- 根据 `--packaging` 调度：
  - `jar` / `war` -> `lib/single.sh`
  - `pom` + `--type=maven` -> `lib/multi-maven.sh`
  - `pom` + `--type=gradle` -> `lib/multi-gradle.sh`
- 子脚本由入口脚本内部 `source` 加载，复用已解析变量，便于后续扩展

## 环境要求

- `bash`
- `curl`
- `unzip`（单模块模式解压 starter.zip 需要）
- `python3`（依赖元数据解析与依赖 ID 校验）
- `pandoc`（`springboot deps list --output=web` 渲染 HTML）
- `glow`（`springboot deps list --output=terminal` 终端渲染，缺失时可直接看缓存文件）
- `mvn` / `xmllint` / `xmlstarlet`（Maven module add 坐标解析，按回退链任选其一）
- 网络访问 Spring Initializr（默认 `https://start.spring.io`，可通过 `INITIALIZR_BASE_URL` 覆盖）
- 说明：脚本会自动探测 Spring Initializr 接口中 Boot 版本参数名（`bootVersion` / `boot-version`），并分别兼容 `metadata/client` 与 `starter.zip` 请求

## 兼容矩阵（建议）

| 项目 | 建议版本/平台 | 说明 |
| --- | --- | --- |
| OS | macOS / Linux | 已覆盖 `open` / `xdg-open` |
| Bash | `4.0+` | 入口与子脚本运行依赖 |
| Zsh | `5.0+` | 仅用于加载 `_springboot` 补全 |
| Java | `17` / `21` / `25` | 与参数校验保持一致 |
| 构建工具 | Maven / Gradle | 与 `--type` 对应 |

## 安装与全局命令配置

### 方式一：Homebrew（推荐）

```bash
brew install hanqunfeng/tap/java-project-generator
```

或分两步：

```bash
brew tap hanqunfeng/tap
brew install java-project-generator
```

安装后请自行安装 **python3**（formula 不会自动安装，生成项目与依赖相关功能需要）：

```bash
brew install python@3.13
```

验证：

```bash
springboot --help
springboot --version
```

升级 / 卸载：

```bash
brew update && brew upgrade java-project-generator
brew uninstall java-project-generator
```

Homebrew 会一并安装 Bash / Zsh 补全；更多说明见 [`formula/README.md`](formula/README.md)。

### 方式二：从源码加入 PATH

下文用 `$REPO_ROOT` 表示本仓库根目录（clone 后的 `java-project-generator` 路径）。复制命令前请替换为实际路径，例如：

```bash
export REPO_ROOT="$(cd /path/to/java-project-generator && pwd)"
```

在当前目录执行：

```bash
chmod +x springboot scripts/check.sh lib/single.sh lib/multi-maven.sh lib/multi-gradle.sh lib/nested-common.sh lib/module-template-common.sh lib/project-common.sh lib/arg-common.sh lib/deps.sh
```

将目录加入 PATH（`zsh` 示例）：

```bash
echo 'export PATH="'"$REPO_ROOT"':$PATH"' >> ~/.zshrc
source ~/.zshrc
```

验证：

```bash
springboot create --name=mydemo
```

## Shell 自动补全

若通过 Homebrew 安装，Bash / Zsh 补全已自动安装，一般无需再配置。从源码使用时，按下方加载即可。

### Bash

```bash
source "$REPO_ROOT/completions/springboot.bash"
```

如需持久化，可追加到 `~/.bashrc`。

说明：`--deps=` 的动态补全依赖本地缓存，建议先执行一次：

```bash
springboot deps list --boot=3.5.14
```

### Zsh

```bash
fpath=("$REPO_ROOT/completions" $fpath)
autoload -Uz compinit && compinit
```

如需持久化，可追加到 `~/.zshrc`。

说明：`--deps=` 的动态补全依赖本地缓存，建议先执行一次：

```bash
springboot deps list --boot=3.5.14
```

## 使用说明

基本用法：

```bash
springboot <command> [options]
```

### 命令说明

- 入口命令：
  - `springboot create`：创建项目（单模块或多模块）
  - `springboot module add|list|remove`：维护多模块项目
  - `springboot deps list|preview|search`：依赖列表、声明预览与关键词搜索
  - `springboot boot list`：查询当前 Initializr 支持的 Spring Boot 版本
- 顶级命令与子命令均支持 `--help` / `-h`
- `--deps` 仅支持 Spring Boot 官方 Initializr 提供的依赖 ID（如 `web`、`data-jpa`、`mysql`）
- 可先执行 `springboot boot list` 查看可创建的 Boot 版本，再执行 `springboot deps list --boot=<版本>` 查看可用依赖 ID
- `create` / `module add`：未指定 `--boot` 时使用当前 Initializr 默认版本；若指定版本不在官方列表中，会提示已不再支持
- 输出默认带彩色提示（成功/警告/错误）；如需关闭可设置环境变量 `NO_COLOR=1`

### 环境变量（可选）

- `NO_COLOR`：关闭彩色输出；设置为任意非空值即可（常见用法：`NO_COLOR=1`）
- `INITIALIZR_BASE_URL`：覆盖 Spring Initializr 基础地址（默认 `https://start.spring.io`）
- `DEPS_CACHE_TTL_SECONDS`：依赖缓存过期秒数（默认 `86400`）
- `GRADLE_DM_PLUGIN_VERSION`：覆盖 Gradle 多模块模板中的 `io.spring.dependency-management` 插件版本，默认 `1.1.7`
  - 示例：`GRADLE_DM_PLUGIN_VERSION=1.1.6 springboot create --name=myproject --type=gradle --packaging=pom --modules=api`
- `EXIT_PARAM` / `EXIT_NETWORK` / `EXIT_FS` / `EXIT_DEP`：子脚本在“脱离入口脚本单独执行/调试”时可通过环境变量兜底退出码（入口 `springboot` 正常调用时使用内置退出码）

## 使用示例

### 最小推荐路径（新用户 3 步）

1) 先确认脚本可用，并查看当前可创建的 Boot 版本：

```bash
springboot --help
springboot boot list
```

2) 用 dry-run 预览执行计划（不创建文件）：

```bash
springboot create --name=mydemo --boot=4.0.7 --dry-run
```

3) 确认参数后正式创建项目：

```bash
springboot create --name=mydemo
```

建议：第一次使用优先从默认参数起步（`maven + jar`），确认流程后再逐步加 `--type`、`--packaging`、`--modules` 等进阶参数。

1) 快速创建单模块（Maven + jar + 默认依赖）：

```bash
springboot create --name=mydemo
```

2) 查看帮助与版本：

```bash
springboot --help
springboot --version
```

3) 仅查看执行计划（不落盘不改文件）：

```bash
springboot create --name=mydemo --dry-run
```

说明：
- dry-run 会在参数校验通过后，输出实际将执行的每一个步骤（含目标路径、关键参数和条件分支）
- 会覆盖单模块、多模块、`module add` 场景
- 仅打印计划，不执行 `mkdir`、`touch`、`curl`、`unzip`、文件写入等操作

4) 创建单模块并自定义关键参数（Gradle + war + Java 21）：

```bash
springboot create --name=mydemo --type=gradle --packaging=war --java=21
```

5) 创建单模块并自定义包名与配置格式（group + pkg + yaml）：

```bash
springboot create --name=mydemo --group=com.lexing --pkg=com.lexing.demo --config=yaml
```

6) 创建单模块并指定项目版本：

```bash
springboot create --name=mydemo --artifact-version=1.2.0
```

7) 查看当前 Initializr 支持的 Boot 版本：

```bash
springboot boot list
```

8) 查看指定 Boot 版本可选依赖（官方 Initializr）：

```bash
springboot deps list --boot=4.0.7 --output=terminal
```

8) 浏览器查看依赖列表（生成并打开 HTML）：

```bash
springboot deps list --boot=3.5.14 --output=web
```

9) 仅输出依赖声明片段（Maven 默认）：

```bash
springboot deps preview --boot=3.5.14 --deps=web,data-jpa,mysql
```

10) 仅输出依赖声明片段（Gradle）：

```bash
springboot deps preview --type=gradle --boot=3.5.14 --deps=web,data-jpa,mysql
```

10.1) 输出 Kotlin DSL 的依赖声明片段：

```bash
springboot deps preview --type=gradle --gradle-dsl=kotlin --language=kotlin --deps=web,data-jpa
```

11) 单模块自定义依赖 ID 列表：

```bash
springboot create --name=mydemo --deps=web,data-jpa,mysql,lombok
```

12) 创建 Maven 多模块项目（父工程 + 子模块 + 统一依赖）：

```bash
springboot create --name=myproject --type=maven --packaging=pom --modules=api,service,common --deps=web,data-jpa
```

13) 创建 Gradle 多模块项目（指定 group / Java / 统一依赖）：

```bash
springboot create --name=myproject --type=gradle --packaging=pom --group=com.lexing --java=21 --modules=api,service,common --deps=web,data-jpa
```

14) 为已有 Maven 多模块项目追加子模块（并指定依赖）：

```bash
springboot module add --name=myproject --type=maven --module=order --deps=webflux
```

15) 在 Maven 项目根下追加 `pom` 类型子模块（用于多层聚合）：

```bash
springboot module add --name=myproject --type=maven --module=platform --module-packaging=pom
```

16) 在 Maven `platform` 子模块下追加 `jar` 子模块：

```bash
springboot module add --name=myproject --type=maven --module-path=platform --module=order-api --module-packaging=jar
```

17) 在 Maven 多层路径下追加子模块：

```bash
springboot module add --name=myproject --type=maven --module-path=platform/common-parent --module=order-service --module-packaging=jar
```

18) 为已有 Gradle 多模块项目追加子模块（并指定依赖）：

```bash
springboot module add --name=myproject --type=gradle --module=order --deps=webflux
```

19) 在 Gradle 项目根下追加聚合模块（`module-packaging=pom` 映射为聚合模块）：

```bash
springboot module add --name=myproject --type=gradle --module=platform --module-packaging=pom
```

20) 在 Gradle 聚合模块下追加业务模块：

```bash
springboot module add --name=myproject --type=gradle --module-path=platform --module=order-api --module-packaging=jar
```

21) 列出与删除子模块：

```bash
springboot module list --name=myproject --type=maven
springboot module remove --name=myproject --type=gradle --module=order
```

22) 搜索依赖：

```bash
springboot deps search --query=redis --boot=3.5.14
```

## 输出结果说明

### 单模块（`jar` / `war`）

- 从 Spring Initializr 下载并解压项目
- 自动删除 `mvnw`、`mvnw.cmd`、`.mvn`、`gradlew`、`gradlew.bat`、`gradle` 和 `HELP.md`
- 自动生成 `.gitignore`

### 多模块 Maven（`--packaging=pom --type=maven`）

- 生成父工程 `pom.xml`（`packaging=pom`）
- 父工程采用 BOM 模式（不继承 `spring-boot-starter-parent`），通过 `spring-boot-dependencies` 管理依赖版本
- 使用 CI-friendly 版本属性 `${revision}`（由 `--artifact-version` 写入 `<revision>`）
- 父工程默认包含 encoding、`maven-compiler-plugin` 与 `spring-boot-maven-plugin` 的 `pluginManagement`
- 父工程以注释形式预置 Spring Cloud / Spring Cloud Alibaba BOM，按需取消注释即可
- 可按 `--modules` 自动生成各子模块目录和子模块 `pom.xml`
- `jar` 子模块依赖由 `--deps` 控制（默认 `web,devtools`）
- 每个子模块默认包含：
  - `src/main/java/...`
  - `src/main/resources/application.properties` 或 `application.yaml`
  - `src/test/java/...`
- `jar` 子模块会自动生成最小可运行的 `*Application.java` 和 `*ApplicationTests.java`，并声明 `spring-boot-maven-plugin`
- 父工程会自动生成 `.gitignore`

### 多模块 Gradle（`--packaging=pom --type=gradle`）

- 生成根 `settings.gradle` 与根 `build.gradle`（`--gradle-dsl=kotlin` 时为 `settings.gradle.kts` 与 `build.gradle.kts`）
- 可按 `--modules` 自动生成各子模块目录和子模块 `build.gradle`（Kotlin DSL 时为 `build.gradle.kts`）
- `jar` 子模块依赖由 `--deps` 控制（默认 `web,devtools`）
- 每个子模块默认包含：
  - `src/main/java/...`
  - `src/main/resources/application.properties` 或 `application.yaml`
  - `src/test/java/...`
- `jar` 子模块会自动生成最小可运行的 `*Application.java` 和 `*ApplicationTests.java`
- 父工程会自动生成 `.gitignore`

## 参数与校验规则

- `springboot module add` 时：
  - 必须提供 `--module`
  - 仅支持 `--packaging=pom`
  - 目标项目目录必须已存在
  - `--module-packaging` 仅支持 `jar` / `pom`
  - `--module-path` 必须定位到项目内已存在的父模块目录（相对路径）
  - Gradle 下 `module-packaging=pom` 表示创建聚合模块（最小 `build.gradle`，不应用 java/spring-boot 插件）
  - Maven 模式会从已有父 `pom.xml` 自动读取真实 `groupId`、`artifactId`、`version`
- `--name`：仅允许字母、数字、下划线、短横线；长度 `5~50`；且首字符必须是字母或数字
- `--group`（groupId）：必须是点分段格式（如 `com.example`），每段首字符为字母或数字，段内允许字母、数字、下划线、短横线
- `--artifact`（artifactId）：仅允许字母、数字、下划线、短横线，且首字符必须是字母或数字（如 `my-demo`、`demo_01`）
- `--artifact-version`：仅允许字母、数字、点、下划线、短横线，且首字符必须是字母或数字（如 `0.0.1`、`1.0.0-SNAPSHOT`）
- `--pkg`（packageName）：必须为 Java 包名格式（如 `com.example.demo`），点分段且每段以字母开头，后续允许字母、数字、下划线；不支持短横线
- `--modules` 中每个模块名：长度 `2~50`，规则同上；重复项会自动去重
- `--module` 校验规则与 `--modules` 中单个模块名一致
- `springboot create` 时，目录已存在会报错退出
- `springboot module add` 时，若子模块目录已存在或已注册在父配置中会报错退出
- `--deps` 在以下场景生效：
  - 单模块创建（`springboot create` 且 `--packaging=jar|war`）
  - 多模块创建（`springboot create` 且 `--packaging=pom`，作用于本次所有 `jar` 子模块）
  - 多模块追加（`springboot module add` 且 `--packaging=pom` 且 `--module-packaging=jar`，作用于新增模块）
- 当 `--module-packaging=pom` 时，`--deps` 会被忽略（聚合模块不写 dependencies）
- 非 dry-run 会按当前 `--boot` 版本实时校验 `--deps` 中每个依赖 ID；非法依赖会报错并提示近似候选

## 常见问题

- 运行后没有自动进入项目目录？
  - 当前设计为全局命令运行，不会修改你当前 shell 工作目录
  - 请手动执行 `cd <项目名>`

- 单模块创建失败并提示下载失败？
  - 先执行 `springboot boot list` 确认当前 Initializr 支持的 Boot 版本
  - 检查网络是否可访问 `https://start.spring.io`（或你设置的 `INITIALIZR_BASE_URL`）
  - 检查本机是否安装并可用 `curl` / `unzip`
  - 若报 400 / 版本无效，改用 `boot list` 中的版本，例如 `--boot=4.0.7`

- `springboot deps list --output=web` 成功打开后提示缺少 glow？
  - 这是非致命提示，不影响网页查看结果
  - 仅在你想在终端渲染 Markdown 表格时才需要安装 `glow`

## 维护说明（开发者）

- 嵌套模块相关公共逻辑集中在 `lib/nested-common.sh`（路径解析、存在性校验、Gradle include 路径生成）
- 参数规范化与 CSV 迭代逻辑集中在 `lib/arg-common.sh`（供入口脚本与多模块脚本复用）
- 依赖/Initializr 交互逻辑集中在 `lib/deps.sh`（缓存、Boot 参数探测、声明提取、deps 子命令实现）
- 模块目录骨架创建公共逻辑集中在 `lib/module-template-common.sh`（`jar` 与聚合模块基础结构、类名/模板写入、dry-run 计划片段）
- 项目级公共逻辑集中在 `lib/project-common.sh`（统一 `.gitignore` 写入）
- Maven/Gradle 各自脚本仅保留构建工具差异化内容（POM/Gradle 文件模板与父配置更新）
- 新增嵌套能力时，优先改公共脚本，再改 `multi-maven.sh` / `multi-gradle.sh` 的工具专属逻辑

公共函数速查表：
- `normalize_csv_unique_common`：CSV 去空白、去重并保持首出现顺序
- `resolve_parent_dir_common`：解析目标父模块目录（项目根或 `module-path`）
- `build_module_dir_common`：拼接目标子模块目录路径
- `ensure_dir_exists_common`：目录存在性校验（不存在即退出）
- `ensure_file_exists_common`：文件存在性校验（不存在即退出）
- `ensure_module_dir_absent_common`：子模块目录冲突校验（已存在即退出）
- `build_gradle_include_path_common`：构建 Gradle include 路径（`a/b` -> `:a:b`）
- `iterate_csv_items_common`：迭代并规范化 CSV 条目（去空白、忽略空项）
- `build_package_subpath_common`：构建包路径子目录（`com.example` + `order-api` -> `com/example/order_api`）
- `create_module_scaffold_common`：按模块类型创建基础骨架（`jar` 生成 src 与配置，`pom` 仅建目录）
- `module_class_name`：模块名转 Spring Boot 启动类名（PascalCase + `Application`）
- `write_module_application_files`：写入 `*Application.java` 与 `*ApplicationTests.java`
- `print_jar_module_scaffold_plan_common`：dry-run 输出 jar 模块通用目录/模板计划
- `write_project_gitignore`：统一写入项目根 `.gitignore`

## 测试

项目已提供基础 bats 用例与统一检查脚本：

```bash
bash scripts/check.sh
# 或仅运行测试
bats test/springboot.bats
```

当前覆盖点包括：
- 基础参数与错误码（缺少必填参数、非法 bootVersion、参数互斥）
- dry-run 核心行为（单模块 / Maven 多模块 / Gradle 多模块）
- `modules` 去重与规范化行为
- `module add` 关键失败分支（项目不存在、缺少 `--module`）
- 冲突检测（Gradle 已包含 include、Maven 子模块目录已存在）
- 公共逻辑回归（多模块创建时统一 `.gitignore` 生成）
- 网络失败路径回归（`deps preview` 拉取失败退出码）
- Maven 坐标解析回退链（`mvn/xmllint/xmlstarlet` 不可用时的 `awk` 回退）
- 多层 `module-path` 挂载行为（嵌套父模块追加子模块）

CI 工作流：`.github/workflows/ci.yml`（shellcheck + bats）

## 后续扩展（规划中）

- 提供离线依赖镜像模式（缓存元数据与模板片段；当前可通过 `INITIALIZR_BASE_URL` 指向镜像站点）
