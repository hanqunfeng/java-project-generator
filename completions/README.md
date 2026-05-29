# Shell 自动补全说明

本目录提供 `springboot` 命令的 Bash 与 Zsh 自动补全脚本。

## 文件说明

- `springboot.bash`：Bash 补全脚本
- `_springboot`：Zsh 补全脚本

## 支持的补全能力

### 命令补全

支持一级命令补全：

```bash
springboot <TAB>
# create module deps
```

支持二级命令补全：

```bash
springboot module <TAB>
# add list remove

springboot deps <TAB>
# list preview search
```

### 参数名补全

支持按命令上下文补全可用参数：

```bash
springboot create --<TAB>
springboot create --na<TAB>
springboot module add --<TAB>
springboot module list --<TAB>
springboot module remove --<TAB>
springboot deps list --<TAB>
springboot deps preview --<TAB>
springboot deps search --<TAB>
```

Zsh 补全会过滤已经使用过的长参数。例如已经输入 `--name=demo` 后，再补全参数时不会继续提示 `--name=`。

### 按子命令的参数补全

**`module list`**

- `--help` `--name=` `--type=` `--module-path=`
- `--type=` 候选：`maven` `gradle`

**`module remove`**

- `--help` `--dry-run` `--name=` `--type=` `--module=` `--module-path=`
- `--type=` 候选：`maven` `gradle`

**`deps list`**

- `--help` `--boot=` `--output=` `--refresh`
- `--output=` 候选：`terminal` `web`

**`deps search`**

- `--help` `--query=` `--boot=` `--refresh`

### 固定取值补全

对固定取值参数提供候选补全：

```bash
springboot create --type=<TAB>
# maven gradle

springboot create --packaging=<TAB>
# jar war pom

springboot module add --module-packaging=<TAB>
# jar pom

springboot create --config=<TAB>
# properties yaml

springboot create --java=<TAB>
# 17 21 25

springboot deps list --output=<TAB>
# terminal web
```

### 依赖 ID 动态补全

`--deps=` 支持从本地依赖缓存中读取 Spring Initializr 依赖 ID 候选，在 `create`、`module add`、`deps preview` 等带 `--deps=` 的命令下均可用。

首次使用前建议先生成缓存：

```bash
springboot deps list --boot=3.5.14
```

然后即可补全：

```bash
springboot create --deps=<TAB>
springboot module add --deps=<TAB>
springboot deps preview --deps=<TAB>
```

## 手动启用

`$REPO_ROOT` 表示仓库根目录，约定与根 [README.md](../README.md) 中「安装与全局命令配置」一致。

### Bash

```bash
source "$REPO_ROOT/completions/springboot.bash"
```

如需持久化，可加入 `~/.bashrc`。

### Zsh

```bash
fpath=("$REPO_ROOT/completions" $fpath)
autoload -Uz compinit && compinit
```

如需持久化，可加入 `~/.zshrc`。

如果修改过补全脚本但没有生效，可刷新 Zsh 补全缓存：

```bash
rm -f ~/.zcompdump*
autoload -Uz compinit && compinit -i
exec zsh
```

## Homebrew 安装后的位置

通过 Homebrew 安装后，补全脚本会被安装到 Homebrew 的补全目录。

在 Intel macOS 默认 Homebrew 路径下通常是：

```text
/usr/local/etc/bash_completion.d/springboot
/usr/local/share/zsh/site-functions/_springboot
```

在 Apple Silicon macOS 默认 Homebrew 路径下通常是：

```text
/opt/homebrew/etc/bash_completion.d/springboot
/opt/homebrew/share/zsh/site-functions/_springboot
```

可以用以下命令确认当前 Homebrew 前缀：

```bash
brew --prefix
```

对应路径为：

```text
$(brew --prefix)/etc/bash_completion.d/springboot
$(brew --prefix)/share/zsh/site-functions/_springboot
```

如果你本地修改了项目中的补全脚本，但当前 shell 使用的是 Homebrew 安装版本，需要同步更新 Homebrew 安装目录下的补全文件，或重新安装对应 formula。
