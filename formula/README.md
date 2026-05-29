# Homebrew Formula 创建说明

本目录保存 `java-project-generator` 的 Homebrew formula 示例：

- `java-project-generator.rb`

它用于让用户通过 Homebrew 安装 `springboot` 命令、依赖脚本、静态资源和 shell 自动补全。

## Formula 是什么

Homebrew formula 是一个 Ruby 文件，用来描述软件如何下载、校验、安装和测试。

当前项目是 shell 脚本工具，不需要编译，因此 formula 的核心工作是：

- 下载指定 tag 的源码压缩包
- 校验 `sha256`
- 安装入口脚本 `springboot`
- 安装运行时依赖目录 `lib/`、`assets/`、`deps-cache/`
- 安装 Bash / Zsh 补全脚本
- 提供一个简单的安装后测试

## 当前 formula 结构

整体由 **元数据区**、**运行时依赖**、**安装逻辑**、**安装后提示**、**安装后测试** 五部分组成：

```text
JavaProjectGenerator (Formula 类)
├── 元数据: desc / homepage / url / sha256 / license
├── depends_on: bash, curl, unzip, glow, pandoc
├── install
│   ├── libexec.install (springboot, lib, completions, assets)
│   ├── deps-cache 空目录创建
│   ├── chmod 0755
│   ├── bin/springboot wrapper
│   └── bash/zsh 补全安装
├── caveats (必装 python3 提示 + 可选工具说明)
└── test (help + dry-run 冒烟测试)
```

与仓库中 [java-project-generator.rb](java-project-generator.rb) 对应的完整示例：

```ruby
class JavaProjectGenerator < Formula
  desc "Generate Spring Boot projects quickly with shell scripts"
  homepage "https://github.com/hanqunfeng/java-project-generator"
  url "https://github.com/hanqunfeng/java-project-generator/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "b81d5cc3902fbf6b7a5cf0386ca406ee7404f040937240d9e4607515229e1209"
  license "MIT"

  depends_on "glow"
  depends_on "pandoc"

  def install
    libexec.install "springboot"
    libexec.install "lib"
    libexec.install "completions"
    libexec.install "assets"
    (libexec/"deps-cache").mkpath
    # chmod、bin wrapper、补全安装 ...
  end

  def caveats
    # python3 必装说明 + 可选 jq/xmllint/xmlstarlet/mvn
  end

  test do
    # --help 与 create --dry-run
  end
end
```

### 元数据字段

| 字段 | 说明 |
| --- | --- |
| `class JavaProjectGenerator < Formula` | Formula 类名，与 Tap 中包名 `java-project-generator` 对应（驼峰命名） |
| `desc` | 一句话描述，`brew info java-project-generator` 会展示 |
| `homepage` | 项目主页 URL |
| `url` | 源码压缩包下载地址，通常指向 GitHub tag 的 `.tar.gz` |
| `sha256` | 与 `url` 对应压缩包的 SHA256，防止下载内容被篡改；**每次改 `url` 必须重算** |
| `license` | 开源许可证标识（本项目为 `MIT`） |

### `depends_on`（formula 自动安装的依赖）

| 依赖 | 用途 |
| --- | --- |
| `glow` | `springboot deps list --output=terminal` |
| `pandoc` | `springboot deps list --output=web` |

未写入 `depends_on`、但在 `caveats` 或文档中说明的依赖见下文「运行时依赖」一节（如 **python3 必装**、jq、xmllint 等）。

### `install` 安装逻辑说明

| 步骤 | 代码要点 | 作用 |
| --- | --- | --- |
| 安装到 `libexec` | `libexec.install "springboot"` 等 | 保留完整目录结构，供运行时 `source lib/*.sh` |
| 创建缓存目录 | `(libexec/"deps-cache").mkpath` | 运行时写入依赖列表缓存，不打包仓库内已有缓存 |
| 可执行权限 | `chmod 0755` | 保证 `springboot` 与 `lib/*.sh` 可直接执行 |
| 命令入口 | `(bin/"springboot").write` + `exec libexec/...` | 在 PATH 中提供 `springboot`，且能正确定位 `SCRIPT_DIR` |
| Shell 补全 | `bash_completion.install` / `zsh_completion.install` | 安装 Bash、Zsh 补全脚本 |

### `caveats` 安装后提示

`brew install` 结束后，`brew info` 会显示该段文字，用于补充 **formula 未自动安装** 的要求：

- **python3（必装）**：需用户自行 `brew install python@3.13`，用于依赖元数据解析与 `--deps` 校验
- **可选**：`jq`、`libxml2`（xmllint）、`xmlstarlet`、`maven`（mvn）
- **网络**：需能访问 Spring Initializr（可用 `INITIALIZR_BASE_URL` 覆盖镜像）

### `test` 安装后测试

| 断言 | 目的 |
| --- | --- |
| `springboot --help` | 验证命令可执行、包装脚本与 `libexec` 路径正常 |
| `springboot create --name=brewtest --dry-run` | 验证参数解析与多模块调度链路（不联网、不落盘） |

测试在隔离环境中运行，**不会**拉取 Initializr，因此不要求测试时已安装 python3；用户实际使用 `create` / `deps` 前仍需按 caveats 安装 python3。

## 为什么使用 `libexec`

`springboot` 不是单文件脚本，它运行时会通过自身路径查找：

- `lib/*.sh`
- `assets/web_style.css`
- `deps-cache/`
- `completions/`

因此不能只把 `springboot` 单独复制到 `bin/`。

当前 formula 使用：

```ruby
libexec.install "springboot"
libexec.install "lib"
libexec.install "completions"
libexec.install "assets"
(libexec/"deps-cache").mkpath
```

这样 Homebrew 会把完整运行目录安装到 formula 的 `libexec` 下。

## 为什么使用 wrapper

不要直接使用：

```ruby
bin.install_symlink libexec/"springboot" => "springboot"
```

更推荐使用 wrapper：

```ruby
(bin/"springboot").write <<~EOS
  #!/usr/bin/env bash
  exec "#{libexec}/springboot" "$@"
EOS
chmod 0755, bin/"springboot"
```

原因是 wrapper 会明确执行 `libexec/springboot`，避免命令从 `/usr/local/bin/springboot` 或 `/opt/homebrew/bin/springboot` 运行时误判脚本目录，导致找不到 `lib/arg-common.sh`。

## 补全脚本安装

当前 formula 会安装 Bash 和 Zsh 补全：

```ruby
bash_completion.install libexec/"completions/springboot.bash" => "springboot"
zsh_completion.install libexec/"completions/_springboot"
```

安装后常见位置：

```text
$(brew --prefix)/etc/bash_completion.d/springboot
$(brew --prefix)/share/zsh/site-functions/_springboot
```

更多补全能力说明见：

```text
completions/README.md
```

## 创建或更新 formula 的流程

### 1. 准备发布 tag

先确保主项目通过检查：

```bash
bash scripts/check.sh
```

然后创建版本 tag，例如：

```bash
git tag v0.3.0
git push origin v0.3.0
```

### 2. 获取源码压缩包地址

GitHub tag 源码包地址格式：

```text
https://github.com/hanqunfeng/java-project-generator/archive/refs/tags/v0.3.0.tar.gz
```

### 3. 计算 sha256

```bash
curl -L -o v0.3.0.tar.gz \
  https://github.com/hanqunfeng/java-project-generator/archive/refs/tags/v0.3.0.tar.gz

shasum -a 256 v0.3.0.tar.gz
```

把输出的 hash 写入 formula 的 `sha256` 字段。

### 4. 更新 formula

修改：

```ruby
url "https://github.com/hanqunfeng/java-project-generator/archive/refs/tags/v0.3.0.tar.gz"
sha256 "<新的 sha256>"
```

### 5. 检查 formula 语法

在项目根目录执行：

```bash
ruby -c formula/java-project-generator.rb
```

期望输出：

```text
Syntax OK
```

### 6. 本地测试安装

可以在本地用 formula 文件直接安装测试：

```bash
brew install --build-from-source ./formula/java-project-generator.rb
```

如果已经安装过，可以先卸载：

```bash
brew uninstall java-project-generator
```

测试命令：

```bash
springboot --help
springboot --version
```

### 7. 发布到 tap 仓库

推荐创建单独的 Homebrew Tap 仓库，如下命令会自动在 `$(brew --prefix)/Homebrew/Library/Taps/` 下创建 Tap 仓库：

```bash
# 注意这里的 tap 仓库名称必须要与后面的 Github 仓库名称一致，这里实际的 tap 名称为 hanqunfeng/tap
brew tap-new hanqunfeng/homebrew-tap 
```

之后将 `java-project-generator.rb` 拷贝到 `Formula` 目录下

目录结构：

```text
hanqunfeng
└── homebrew-tap
    ├── Formula
    │   └── java-project-generator.rb
    └── README.md
```


在 Github 中创建用于存储上面的 Homebrew Tap 的远程仓库，比如：

```bash
hanqunfeng/homebrew-tap
```

绑定远程仓库并提交：

```bash
cd $(brew --repo hanqunfeng/homebrew-tap)
git add .
git commit -m "java-project-generator v1.0.1"
git remote add origin https://github.com/hanqunfeng/homebrew-tap.git
git push -u origin main
```

为了保证 Formula 文件语法准确，在提交代码前可以先进行如下测试，确认没问题再 push。

```bash
brew style --fix hanqunfeng/tap
brew audit --tap=hanqunfeng/tap
```

用户安装方式：

```bash
# 先安装tap
brew tap hanqunfeng/tap
# 再安装工具
brew install java-project-generator
```

也可以直接安装：

```bash
brew install hanqunfeng/tap/java-project-generator
```

卸载方式：

```bash
brew uninstall java-project-generator
```

卸载tap

```bash
brew untap hanqunfeng/tap
```

## 运行时依赖

通过 `brew install java-project-generator` 时，formula 会自动安装以下工具：

| 工具 | 用途 |
| --- | --- |
| bash | 多模块模板生成（需 Bash 4+） |
| curl | 从 Spring Initializr 下载项目与元数据 |
| unzip | 单模块 jar/war 解压 starter.zip |
| glow | `springboot deps list --output=terminal` |
| pandoc | `springboot deps list --output=web` |

**必须自行安装**（formula 不会安装，使用前请先装好）：

| 工具 | 安装方式 | 用途 |
| --- | --- | --- |
| python3 | `brew install python@3.13` | 依赖列表缓存、`--deps` 校验、Initializr 元数据解析（**必需**） |

安装后 `brew info java-project-generator` 的 **Caveats** 中会再次强调 python3 为必装项。

**可选依赖**（Caveats 中说明，按需安装）：

| 工具 | 安装方式 | 用途 |
| --- | --- | --- |
| jq | `brew install jq` | 可选 JSON 工具 |
| xmllint | `brew install libxml2` | Maven `module add` 解析父 pom |
| xmlstarlet | `brew install xmlstarlet` | 同上，第二回退 |
| mvn | `brew install maven` | Maven `module add` 时更准确的坐标解析（脚本有 awk 兜底） |

## 注意事项

- 每次修改 `url` 后都必须重新计算 `sha256`
- `url` 指向的 tag 内容一旦发布后不建议修改
- 如果补全脚本变更，需要重新发布 tag 并更新 formula
- `deps-cache/` 是运行时缓存目录，formula 中用 `mkpath` 创建即可，不建议依赖仓库中的缓存文件
- 如果后续增加新的运行时目录，也要同步加到 `libexec.install`
- 推送到Github时，如果提示缺少权限，需要给仓库添加权限。在 Github 中添加一个 Personal Access Token，并添加权限 `repo` 和 `workflow`，重新推送
```bash
# 设置远程仓库地址，注意替换为你的仓库地址，并且密钥替换为实际的密钥
git remote set-url origin https://ghp_xxxxx@github.com/hanqunfeng/homebrew-tap.git
git push -u origin main
```
