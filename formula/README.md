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

```ruby
class JavaProjectGenerator < Formula
  desc "Generate Spring Boot projects quickly with shell scripts"
  homepage "https://github.com/hanqunfeng/java-project-generator"
  url "https://github.com/hanqunfeng/java-project-generator/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "6db7dfa98891f4cadce84c9354a31e49884d6a92626b8799fed4205795badec2"
  license "MIT"

  def install
    # install logic
  end

  test do
    # smoke test
  end
end
```

字段说明：

- `desc`：简短描述，会显示在 `brew info` 中
- `homepage`：项目主页
- `url`：源码压缩包地址，通常指向 GitHub tag
- `sha256`：源码压缩包校验值，确保下载内容未被篡改
- `license`：项目许可证
- `install`：安装逻辑
- `test`：安装后测试逻辑

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
git remote add origin https://github.com/hanqunfeng/homebrew-tag.git
git push -u origin main
```


用户安装方式：

```bash
brew tap hanqunfeng/tap
brew install java-project-generator
```

也可以直接安装：

```bash
brew install hanqunfeng/tap/java-project-generator
```

卸载方式：

```bash
brew uninstall hanqunfeng/homebrew-tap/java-project-generator
```

## 注意事项

- 每次修改 `url` 后都必须重新计算 `sha256`
- `url` 指向的 tag 内容一旦发布后不建议修改
- 如果补全脚本变更，需要重新发布 tag 并更新 formula
- `deps-cache/` 是运行时缓存目录，formula 中用 `mkpath` 创建即可，不建议依赖仓库中的缓存文件
- 如果后续增加新的运行时目录，也要同步加到 `libexec.install`
- 推送到Github时，如果提示缺少权限，需要给仓库添加权限。在 Github 中添加一个 Personal Access Token，并添加权限 `repo` 和 `workflow`，重新推送
```bash
# 设置远程仓库地址，注意替换为你的仓库地址，并且密钥替换为实际的密钥
git remote set-url origin https://ghp_xxxxx@github.com/hanqunfeng/homebrew-tag.git
git push -u origin main
```
