# Homebrew Formula 使用与发布说明

本目录保存 `java-project-generator` 的 Homebrew formula：

- [`java-project-generator.rb`](java-project-generator.rb)

通过它，用户可用 Homebrew 安装 `springboot` 命令、依赖脚本、静态资源和 shell 补全。

---

## 目录

1. [用户：安装 / 升级 / 卸载](#1-用户安装--升级--卸载)
2. [维护者：一键发布新版本（推荐）](#2-维护者一键发布新版本推荐)
3. [维护者：首次搭建 Tap（只需一次）](#3-维护者首次搭建-tap只需一次)
4. [Formula 结构速览](#4-formula-结构速览)
5. [设计要点：libexec、wrapper、补全](#5-设计要点libexecwrapper补全)
6. [手工发布流程（备用）](#6-手工发布流程备用)
7. [运行时依赖](#7-运行时依赖)
8. [注意事项与排障](#8-注意事项与排障)

---

## 1. 用户：安装 / 升级 / 卸载

```bash
# 安装（二选一）
brew tap hanqunfeng/tap
brew install java-project-generator

# 或一行安装
brew install hanqunfeng/tap/java-project-generator
```

安装后请按提示安装 **python3**（formula 不会自动装）：

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
brew untap hanqunfeng/tap    # 可选：卸掉整个 tap
```

---

## 2. 维护者：一键发布新版本（推荐）

日常发版请用仓库根目录脚本：

```text
scripts/release-formula.sh
```

它会自动完成「升版本 → 打 tag → 算 sha256 → 更新 formula → 同步到本地 Tap → 推送」整条链路，对应下文手工流程中的全部步骤。

### 2.1 前置条件

| 条件 | 说明 |
| --- | --- |
| 工作区干净 | `git status` 无未提交变更（`--resume` 除外） |
| 远程可推送 | 主仓库 `origin` 与 tap 仓库均有 push 权限 |
| 本地已有 Tap | `cd "$(brew --repo hanqunfeng/homebrew-tap)"` 可用（见 [第 3 节](#3-维护者首次搭建-tap只需一次)） |
| 常用工具 | `git`、`curl`、`shasum`/`sha256sum`、`brew`、`ruby` |

相关辅助脚本：

| 脚本 | 作用 |
| --- | --- |
| `scripts/check.sh` | 发布前 shellcheck + bats |
| `scripts/sync-version.sh` | 同步 `SCRIPT_VERSION` 与 formula 的 `url` / `sha256` |
| `scripts/release-formula.sh` | 端到端自动发布 |

### 2.2 常用命令

先预览（不改任何文件、不推送）：

```bash
bash scripts/release-formula.sh patch --dry-run
```

正式发布（按 semver 自动升版本）：

```bash
# 假设当前最新 tag 为 v1.0.6：
bash scripts/release-formula.sh patch    # → v1.0.7
bash scripts/release-formula.sh minor    # → v1.1.0
bash scripts/release-formula.sh major    # → v2.0.0

# 或指定确切版本号
bash scripts/release-formula.sh --version 1.2.0
```

脚本会先打印发布计划，确认后执行。常用选项：

| 选项 | 含义 |
| --- | --- |
| `--dry-run` | 只打印将执行的命令，不真正改动 |
| `--yes` / `-y` | 跳过交互确认 |
| `--skip-check` | 跳过 `scripts/check.sh` |
| `--skip-tap-audit` | 跳过 `brew style` / `brew audit` |
| `--no-push` | 不推远程（无法完成 sha256，一般仅调试用） |
| `--resume X.Y.Z` | tag 已推送但后续失败时，从算 sha256 起续跑 |

### 2.3 脚本实际做了什么

```text
1. 根据最新 git tag + bump 类型（或 --version）计算新版本
2. 运行 scripts/check.sh
3. 更新 springboot 中的 SCRIPT_VERSION
4. 提交主仓库，创建并推送 annotated tag（如 v1.0.7）
5. 从 GitHub 下载该 tag 的 .tar.gz，计算 sha256（带重试）
6. 调用 sync-version.sh 更新 formula 的 url / sha256
7. 提交并推送主仓库中的 formula 变更
8. 拷贝 formula 到本地 Tap，执行 brew style / brew audit
9. 提交并推送 Tap 仓库
```

说明：正确的 `sha256` 只能在 tag 推上 GitHub 之后得到，因此 formula 的最终更新会落在 **tag 之后的一次 commit**。Homebrew 实际读取的是 **Tap 仓库**里的 formula，主仓库 `formula/` 作为同步源与示例即可。

### 2.4 中途失败怎么续跑

若 tag 已推送成功，但算 sha256 / 更新 formula / 同步 Tap 时失败，**不要重新 bump**，用续跑：

```bash
bash scripts/release-formula.sh --resume 1.0.7 --yes
```

续跑会跳过升版本与打 tag，从下载源码包计算 sha256 起继续。

### 2.5 发布后验证

```bash
brew update
brew upgrade java-project-generator
springboot --version    # 应显示新版本号
```

也可用本地 formula 文件冒烟：

```bash
brew uninstall java-project-generator   # 若已安装
brew install --build-from-source ./formula/java-project-generator.rb
springboot --help
springboot --version
```

---

## 3. 维护者：首次搭建 Tap（只需一次）

若本机还没有 Tap，按下面做一次即可；之后发版只需跑 [第 2 节](#2-维护者一键发布新版本推荐) 的脚本。

```bash
# tap 仓库名须与 GitHub 仓库名一致；brew 侧简写为 hanqunfeng/tap
brew tap-new hanqunfeng/homebrew-tap
```

本地目录大致为：

```text
$(brew --repo hanqunfeng/homebrew-tap)
├── Formula/
│   └── java-project-generator.rb   # 由发布脚本自动拷贝更新
└── README.md
```

在 GitHub 创建空仓库 `hanqunfeng/homebrew-tap`，绑定并推送：

```bash
cd "$(brew --repo hanqunfeng/homebrew-tap)"
# 首次可先放入 formula，或等 release-formula.sh 自动拷贝后再推
git remote add origin https://github.com/hanqunfeng/homebrew-tap.git
git push -u origin main
```

提交前建议检查（发布脚本默认也会跑）：

```bash
brew style --fix hanqunfeng/tap
brew audit --tap=hanqunfeng/tap
```

若 `git push` 提示权限不足，可为 GitHub 配置带 `repo`（及按需 `workflow`）权限的 Personal Access Token，并设置远程地址后重试：

```bash
git remote set-url origin https://<TOKEN>@github.com/hanqunfeng/homebrew-tap.git
git push -u origin main
```

---

## 4. Formula 结构速览

Homebrew formula 是一个 Ruby 文件，描述如何下载、校验、安装和测试软件。本项目是 shell 工具、无需编译，formula 主要负责：

- 下载指定 tag 的源码包并校验 `sha256`
- 安装 `springboot`、`lib/`、`assets/`、补全脚本
- 创建运行时 `deps-cache/` 目录
- 提供安装后冒烟测试

整体结构：

```text
JavaProjectGenerator (Formula 类)
├── 元数据: desc / homepage / url / sha256 / license
├── depends_on: glow, pandoc
├── install
│   ├── libexec.install (springboot, lib, completions, assets)
│   ├── deps-cache 空目录创建
│   ├── chmod 0755
│   ├── bin/springboot wrapper
│   └── bash/zsh 补全安装
├── caveats (必装 python3 + 可选工具说明)
└── test (help + dry-run 冒烟测试)
```

示例骨架（完整内容见 [`java-project-generator.rb`](java-project-generator.rb)）：

```ruby
class JavaProjectGenerator < Formula
  desc "Generate Spring Boot projects quickly with shell scripts"
  homepage "https://github.com/hanqunfeng/java-project-generator"
  url "https://github.com/hanqunfeng/java-project-generator/archive/refs/tags/v1.0.6.tar.gz"
  sha256 "be5b0b41ad3730d9dbf8d907ca33b70a6bf77e7ba816431ce94a778742d71b0a"
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
| `class JavaProjectGenerator < Formula` | 类名对应包名 `java-project-generator`（驼峰） |
| `desc` | 一句话描述，`brew info` 会展示 |
| `homepage` | 项目主页 |
| `url` | 源码包地址，通常指向 GitHub tag 的 `.tar.gz` |
| `sha256` | 与 `url` 对应；**每次改 `url` 必须重算** |
| `license` | 本项目为 `MIT` |

### `depends_on`

| 依赖 | 用途 |
| --- | --- |
| `glow` | `springboot deps list --output=terminal` |
| `pandoc` | `springboot deps list --output=web` |

未写入 `depends_on` 的依赖见 [第 7 节](#7-运行时依赖)（如 **python3 必装**）。

### `install` 要点

| 步骤 | 作用 |
| --- | --- |
| `libexec.install ...` | 保留完整目录，供运行时 `source lib/*.sh` |
| `(libexec/"deps-cache").mkpath` | 运行时缓存目录，不打包仓库内已有缓存 |
| `chmod 0755` | 保证脚本可执行 |
| `bin/springboot` wrapper | PATH 入口，并正确定位 `SCRIPT_DIR` |
| bash/zsh completion | 安装自动补全 |

### `caveats` / `test`

- **caveats**：提醒用户自行安装 python3，以及可选的 jq / xmllint / xmlstarlet / mvn；网络需能访问 Spring Initializr（可用 `INITIALIZR_BASE_URL` 覆盖）。
- **test**：`springboot --help` 与 `create --dry-run`；隔离环境不联网，不要求测试时已装 python3。

本地语法检查：

```bash
ruby -c formula/java-project-generator.rb
# 期望: Syntax OK
```

---

## 5. 设计要点：libexec、wrapper、补全

### 为什么用 `libexec`

`springboot` 不是单文件脚本，运行时会按自身路径查找 `lib/*.sh`、`assets/`、`deps-cache/`、`completions/`，因此不能只把入口拷到 `bin/`。

```ruby
libexec.install "springboot"
libexec.install "lib"
libexec.install "completions"
libexec.install "assets"
(libexec/"deps-cache").mkpath
```

### 为什么用 wrapper（而不是 symlink）

```ruby
# 不推荐
bin.install_symlink libexec/"springboot" => "springboot"

# 推荐
(bin/"springboot").write <<~EOS
  #!/usr/bin/env bash
  exec "#{libexec}/springboot" "$@"
EOS
chmod 0755, bin/"springboot"
```

wrapper 保证始终执行 `libexec/springboot`，避免从 `/usr/local/bin` 或 `/opt/homebrew/bin` 启动时误判脚本目录、找不到 `lib/arg-common.sh`。

### 补全安装

```ruby
bash_completion.install libexec/"completions/springboot.bash" => "springboot"
zsh_completion.install libexec/"completions/_springboot"
```

常见安装位置：

```text
$(brew --prefix)/etc/bash_completion.d/springboot
$(brew --prefix)/share/zsh/site-functions/_springboot
```

更多说明见 `completions/README.md`。

---

## 6. 手工发布流程（备用）

一般请用 [第 2 节](#2-维护者一键发布新版本推荐) 的自动脚本。仅在排查或脚本不可用时按下列步骤手工操作。

### 6.1 检查与打 tag

```bash
bash scripts/check.sh
git tag v0.3.0
git push origin v0.3.0
```

### 6.2 下载源码包并计算 sha256

```text
https://github.com/hanqunfeng/java-project-generator/archive/refs/tags/v0.3.0.tar.gz
```

```bash
curl -L -o v0.3.0.tar.gz \
  https://github.com/hanqunfeng/java-project-generator/archive/refs/tags/v0.3.0.tar.gz
shasum -a 256 v0.3.0.tar.gz
```

### 6.3 同步版本与 formula

可直接改 `formula/java-project-generator.rb` 的 `url` / `sha256`，或：

```bash
bash scripts/sync-version.sh 0.3.0 <sha256>
```

### 6.4 语法检查与本地安装测试

```bash
ruby -c formula/java-project-generator.rb
brew uninstall java-project-generator   # 若已安装
brew install --build-from-source ./formula/java-project-generator.rb
springboot --help
springboot --version
```

### 6.5 同步到 Tap 并推送

```bash
cp formula/java-project-generator.rb \
  "$(brew --repo hanqunfeng/homebrew-tap)/Formula/"

cd "$(brew --repo hanqunfeng/homebrew-tap)"
brew style --fix hanqunfeng/tap
brew audit --tap=hanqunfeng/tap
git add Formula/java-project-generator.rb
git commit -m "java-project-generator v0.3.0"
git push
```

---

## 7. 运行时依赖

`brew install java-project-generator` 时，formula / Homebrew 环境通常已覆盖：

| 工具 | 用途 |
| --- | --- |
| bash | 多模块模板生成（需 Bash 4+） |
| curl | 访问 Spring Initializr |
| unzip | 单模块 jar/war 解压 starter.zip |
| glow | `deps list --output=terminal` |
| pandoc | `deps list --output=web` |

**必须自行安装**（formula 不会装）：

| 工具 | 安装方式 | 用途 |
| --- | --- | --- |
| python3 | `brew install python@3.13` | 依赖缓存、`--deps` 校验、Initializr 元数据解析 |

`brew info java-project-generator` 的 Caveats 会再次提示。

**可选依赖**：

| 工具 | 安装方式 | 用途 |
| --- | --- | --- |
| jq | `brew install jq` | 可选 JSON 工具 |
| xmllint | `brew install libxml2` | Maven `module add` 解析父 pom |
| xmlstarlet | `brew install xmlstarlet` | 同上，第二回退 |
| mvn | `brew install maven` | 更准确的坐标解析（脚本有 awk 兜底） |

---

## 8. 注意事项与排障

- 每次修改 `url` 后都必须重新计算 `sha256`
- 已发布 tag 的内容不建议再改；有问题请发新版本
- 补全脚本或运行时目录变更后，需重新打 tag 并更新 formula；新增运行时目录时同步加到 `libexec.install`
- `deps-cache/` 用 `mkpath` 创建即可，不要依赖仓库里已有缓存文件
- 发布脚本要求主仓库工作区干净；先提交功能改动，再跑 `release-formula.sh`
- tag 已推送但后续失败：用 `--resume X.Y.Z`，不要重复 bump
- Tap 推送权限问题：见 [第 3 节](#3-维护者首次搭建-tap只需一次) 的 Token 说明
