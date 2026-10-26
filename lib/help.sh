#!/usr/bin/env bash
# 帮助文案。默认英文；OUTPUT_LANG=zh 时保持原有中文。

print_help_root() {
    if [ "${OUTPUT_LANG}" = "zh" ]; then
        cat <<'EOF'
用法:
  springboot <command> [options]

说明:
  Spring Boot 项目脚手架（create / module / deps / boot）
  每个命令和子命令均支持 --help 或 -h 查看说明

命令:
  create            创建项目（单模块或多模块）
  module            模块操作（add / list / remove）
  deps              依赖工具（list / preview / search）
  boot              Boot 版本工具（list）

通用选项:
  --help, -h        显示帮助信息并退出
  --version, -v     显示脚本版本并退出
  --zh              使用中文输出

环境变量（全局）:
  NO_COLOR=1                     关闭彩色输出（成功/警告/错误）
  GRADLE_DM_PLUGIN_VERSION=<ver> 覆盖 Gradle 多模块模板中的 dependency-management 插件版本（默认 1.1.7）
  INITIALIZR_BASE_URL=<url>      覆盖 Spring Initializr 基础地址（默认 https://start.spring.io）
  DEPS_CACHE_TTL_SECONDS=<秒>      依赖缓存过期秒数（默认 86400）

快速示例:
  springboot boot list
  springboot create --name=mydemo
  springboot module add --name=myproject --type=maven --module=order --deps=webflux
  springboot deps list --boot=3.5.14 --output=terminal
  springboot deps preview --type=gradle --deps=web,data-jpa --boot=3.5.14
  springboot module list --name=myproject --type=maven
EOF
        return 0
    fi
    cat <<'EOF'
Usage:
  springboot <command> [options]

Description:
  Spring Boot project scaffolder (create / module / deps / boot).
  Every command and subcommand accepts --help or -h.

Commands:
  create            Create a project (single-module or multi-module)
  module            Module operations (add / list / remove)
  deps              Dependency tools (list / preview / search)
  boot              Boot version tools (list)

Common options:
  --help, -h        Show help and exit
  --version, -v     Show the script version and exit
  --zh              Print messages in Chinese

Environment variables (global):
  NO_COLOR=1                     Disable colored output (success/warning/error)
  GRADLE_DM_PLUGIN_VERSION=<ver> Override the dependency-management plugin version in Gradle multi-module templates (default 1.1.7)
  INITIALIZR_BASE_URL=<url>      Override the Spring Initializr base URL (default https://start.spring.io)
  DEPS_CACHE_TTL_SECONDS=<seconds> Dependency cache TTL in seconds (default 86400)

Examples:
  springboot boot list
  springboot create --name=mydemo
  springboot module add --name=myproject --type=maven --module=order --deps=webflux
  springboot deps list --boot=3.5.14 --output=terminal
  springboot deps preview --type=gradle --deps=web,data-jpa --boot=3.5.14
  springboot module list --name=myproject --type=maven
EOF
}

print_help_boot() {
    if [ "${OUTPUT_LANG}" = "zh" ]; then
        cat <<'EOF'
用法:
  springboot boot <subcommand> [options]

子命令:
  list              查询当前 Initializr 支持的 Spring Boot 版本

选项:
  --help, -h        显示帮助信息并退出
  --zh              使用中文输出

示例:
  springboot boot list
EOF
        return 0
    fi
    cat <<'EOF'
Usage:
  springboot boot <subcommand> [options]

Subcommands:
  list              List Spring Boot versions supported by the current Initializr

Options:
  --help, -h        Show help and exit
  --zh              Print messages in Chinese

Examples:
  springboot boot list
EOF
}

print_help_boot_list() {
    if [ "${OUTPUT_LANG}" = "zh" ]; then
        cat <<'EOF'
用法:
  springboot boot list [选项]

说明:
  查询当前 Initializr 支持、可用于项目创建的 Spring Boot 版本列表。
  数据来自 ${INITIALIZR_BASE_URL}/metadata/client 的 bootVersion 字段。

选项:
  --refresh                    强制刷新 Boot 版本缓存
  --help, -h                   显示本命令帮助并退出
  --zh                         使用中文输出

相关环境变量:
  INITIALIZR_BASE_URL=<url>      覆盖 Spring Initializr 基础地址（默认 https://start.spring.io）
  DEPS_CACHE_TTL_SECONDS=<秒>      版本列表缓存过期秒数（默认 86400）

示例:
  springboot boot list
  springboot boot list --refresh
EOF
        return 0
    fi
    cat <<'EOF'
Usage:
  springboot boot list [options]

Description:
  List Spring Boot versions that the current Initializr can use to create projects.
  Data comes from the bootVersion field of ${INITIALIZR_BASE_URL}/metadata/client.

Options:
  --refresh                    Force a refresh of the Boot version cache
  --help, -h                   Show this command's help and exit
  --zh                         Print messages in Chinese

Related environment variables:
  INITIALIZR_BASE_URL=<url>      Override the Spring Initializr base URL (default https://start.spring.io)
  DEPS_CACHE_TTL_SECONDS=<seconds> Version-list cache TTL in seconds (default 86400)

Examples:
  springboot boot list
  springboot boot list --refresh
EOF
}

print_help_create() {
    if [ "${OUTPUT_LANG}" = "zh" ]; then
        cat <<EOF
用法:
  springboot create --name=<项目名> [选项...]

说明:
  创建 Spring Boot 项目，支持单模块（jar/war）与多模块（packaging=pom）。

必填:
  --name=<值>                  项目名（目录名 / artifactId）

选项:
  --type=<值>                  构建工具：maven | gradle（默认 maven）
  --packaging=<值>             打包方式：jar | war | pom（默认 jar）
  --modules=<值>               子模块列表（逗号分隔，仅 packaging=pom 生效）
  --deps=<值>                  依赖ID列表（默认 ${DEFAULT_DEPS}）
                               仅支持 Spring Boot 官方 Initializr 提供的依赖ID
                               可先执行 springboot deps list --boot=<版本> 查看可用依赖ID
                               - 单模块(jar/war): 作用于当前项目
                               - 多模块(pom): 作用于本次创建的 jar 子模块
  --boot=<值>                  Spring Boot 版本（默认取当前 Initializr 默认版本，可用 springboot boot list 查看）
  --config=<值>                配置文件格式：properties | yaml（默认 properties）
  --java=<值>                  Java 版本：17 | 21 | 25（默认 17）
  --language=<值>              代码语言：java | kotlin | groovy（默认 java）
  --gradle-dsl=<值>            Gradle DSL：groovy | kotlin（默认 groovy）
  --group=<值>                 Group Id（默认 com.example）
  --artifact=<值>              Artifact Id（默认同 --name）
  --artifact-version=<值>      项目版本（默认 0.0.1）
  --desc=<值>                  项目描述（默认 Demo project for Spring Boot）
  --pkg=<值>                   根包名（默认同 --group，自动将 '-' 替换为 '_'）
  --dry-run                    仅打印执行计划，不创建或修改任何文件
  --help, -h                   显示本命令帮助并退出
  --zh                         使用中文输出

相关环境变量:
  NO_COLOR=1                     关闭彩色输出
  GRADLE_DM_PLUGIN_VERSION=<ver> 在 --type=gradle 且多模块场景下覆盖 dependency-management 插件版本
  INITIALIZR_BASE_URL=<url>      覆盖 Spring Initializr 基础地址（默认 https://start.spring.io）

示例:
  springboot create --name=mydemo
  springboot create --name=mydemo --type=gradle --packaging=war --java=21
  springboot create --name=myproject --type=maven --packaging=pom --modules=api,service --deps=web,data-jpa --dry-run
  springboot create --name=mydemo --type=gradle --gradle-dsl=kotlin --language=kotlin
EOF
        return 0
    fi
    cat <<EOF
Usage:
  springboot create --name=<project-name> [options...]

Description:
  Create a Spring Boot project. Single-module (jar/war) and multi-module (packaging=pom) are supported.

Required:
  --name=<value>               Project name (directory name / artifactId)

Options:
  --type=<value>               Build tool: maven | gradle (default maven)
  --packaging=<value>          Packaging: jar | war | pom (default jar)
  --modules=<value>            Module list, comma-separated (only when packaging=pom)
  --deps=<value>               Dependency IDs (default ${DEFAULT_DEPS})
                               Only dependency IDs provided by the official Spring Boot Initializr are accepted
                               Run springboot deps list --boot=<version> to see available IDs
                               - single-module (jar/war): applied to the project
                               - multi-module (pom): applied to jar modules created this time
  --boot=<value>               Spring Boot version (default: current Initializr default; see springboot boot list)
  --config=<value>             Config format: properties | yaml (default properties)
  --java=<value>               Java version: 17 | 21 | 25 (default 17)
  --language=<value>           Language: java | kotlin | groovy (default java)
  --gradle-dsl=<value>         Gradle DSL: groovy | kotlin (default groovy)
  --group=<value>              Group Id (default com.example)
  --artifact=<value>           Artifact Id (default: same as --name)
  --artifact-version=<value>   Project version (default 0.0.1)
  --desc=<value>               Description (default Demo project for Spring Boot)
  --pkg=<value>                Root package (default: same as --group, with '-' replaced by '_')
  --dry-run                    Print the execution plan only; do not create or modify files
  --help, -h                   Show this command's help and exit
  --zh                         Print messages in Chinese

Related environment variables:
  NO_COLOR=1                     Disable colored output
  GRADLE_DM_PLUGIN_VERSION=<ver> Override the dependency-management plugin version for --type=gradle multi-module projects
  INITIALIZR_BASE_URL=<url>      Override the Spring Initializr base URL (default https://start.spring.io)

Examples:
  springboot create --name=mydemo
  springboot create --name=mydemo --type=gradle --packaging=war --java=21
  springboot create --name=myproject --type=maven --packaging=pom --modules=api,service --deps=web,data-jpa --dry-run
  springboot create --name=mydemo --type=gradle --gradle-dsl=kotlin --language=kotlin
EOF
}

print_help_module() {
    if [ "${OUTPUT_LANG}" = "zh" ]; then
        cat <<'EOF'
用法:
  springboot module <subcommand> [options]

子命令:
  add               向已有多模块项目追加子模块
  list              列出当前多模块项目下的子模块
  remove            从多模块项目中移除子模块

选项:
  --help, -h        显示帮助信息并退出
  --zh              使用中文输出

示例:
  springboot module add --name=myproject --type=maven --module=order --deps=webflux
  springboot module list --name=myproject --type=gradle
  springboot module remove --name=myproject --type=gradle --module=api
EOF
        return 0
    fi
    cat <<'EOF'
Usage:
  springboot module <subcommand> [options]

Subcommands:
  add               Add a module to an existing multi-module project
  list              List modules in a multi-module project
  remove            Remove a module from a multi-module project

Options:
  --help, -h        Show help and exit
  --zh              Print messages in Chinese

Examples:
  springboot module add --name=myproject --type=maven --module=order --deps=webflux
  springboot module list --name=myproject --type=gradle
  springboot module remove --name=myproject --type=gradle --module=api
EOF
}

print_help_module_add() {
    if [ "${OUTPUT_LANG}" = "zh" ]; then
        cat <<EOF
用法:
  springboot module add --name=<项目名> --module=<子模块名> [选项...]

说明:
  向已有多模块项目追加子模块。
  默认按聚合模式处理（packaging=pom）。

必填:
  --name=<值>                  目标项目名
  --module=<值>                新增子模块名

选项:
  --type=<值>                  构建工具：maven | gradle（默认 maven）
  --packaging=<值>             仅支持 pom（未显式传入时默认按 pom 处理）
  --module-packaging=<值>      子模块打包方式：jar | pom（默认 jar）
  --module-path=<值>           父模块路径（相对项目根，默认挂载到项目根）
  --deps=<值>                  依赖ID列表（默认 ${DEFAULT_DEPS}，仅 module-packaging=jar 生效）
                               仅支持 Spring Boot 官方 Initializr 提供的依赖ID
  --boot=<值>                  Spring Boot 版本（默认取当前 Initializr 默认版本，可用 springboot boot list 查看）
  --config=<值>                配置文件格式：properties | yaml（默认 properties）
  --java=<值>                  Java 版本：17 | 21 | 25（默认 17）
  --language=<值>              代码语言：java | kotlin | groovy（默认 java）
  --gradle-dsl=<值>            Gradle DSL：groovy | kotlin（默认 groovy）
  --group=<值>                 Group Id（默认 com.example）
  --pkg=<值>                   根包名（默认同 --group，自动将 '-' 替换为 '_'）
  --dry-run                    仅打印执行计划，不创建或修改任何文件
  --help, -h                   显示本命令帮助并退出
  --zh                         使用中文输出

相关环境变量:
  NO_COLOR=1                     关闭彩色输出
  GRADLE_DM_PLUGIN_VERSION=<ver> 在 --type=gradle 且 module-packaging=jar 时覆盖 dependency-management 插件版本
  INITIALIZR_BASE_URL=<url>      覆盖 Spring Initializr 基础地址（默认 https://start.spring.io）

示例:
  springboot module add --name=myproject --type=maven --module=order --deps=webflux
  springboot module add --name=myproject --type=gradle --module=api --module-path=platform/common --deps=web,data-jpa
  springboot module add --name=myproject --type=maven --module=platform --module-packaging=pom
EOF
        return 0
    fi
    cat <<EOF
Usage:
  springboot module add --name=<project-name> --module=<module-name> [options...]

Description:
  Add a module to an existing multi-module project.
  Aggregator mode is the default (packaging=pom).

Required:
  --name=<value>               Target project name
  --module=<value>             Module name to add

Options:
  --type=<value>               Build tool: maven | gradle (default maven)
  --packaging=<value>          Only pom is supported (defaults to pom when omitted)
  --module-packaging=<value>   Module packaging: jar | pom (default jar)
  --module-path=<value>        Parent module path, relative to the project root (default: project root)
  --deps=<value>               Dependency IDs (default ${DEFAULT_DEPS}; only when module-packaging=jar)
                               Only dependency IDs provided by the official Spring Boot Initializr are accepted
  --boot=<value>               Spring Boot version (default: current Initializr default; see springboot boot list)
  --config=<value>             Config format: properties | yaml (default properties)
  --java=<value>               Java version: 17 | 21 | 25 (default 17)
  --language=<value>           Language: java | kotlin | groovy (default java)
  --gradle-dsl=<value>         Gradle DSL: groovy | kotlin (default groovy)
  --group=<value>              Group Id (default com.example)
  --pkg=<value>                Root package (default: same as --group, with '-' replaced by '_')
  --dry-run                    Print the execution plan only; do not create or modify files
  --help, -h                   Show this command's help and exit
  --zh                         Print messages in Chinese

Related environment variables:
  NO_COLOR=1                     Disable colored output
  GRADLE_DM_PLUGIN_VERSION=<ver> Override the dependency-management plugin version for --type=gradle when module-packaging=jar
  INITIALIZR_BASE_URL=<url>      Override the Spring Initializr base URL (default https://start.spring.io)

Examples:
  springboot module add --name=myproject --type=maven --module=order --deps=webflux
  springboot module add --name=myproject --type=gradle --module=api --module-path=platform/common --deps=web,data-jpa
  springboot module add --name=myproject --type=maven --module=platform --module-packaging=pom
EOF
}

print_help_module_list() {
    if [ "${OUTPUT_LANG}" = "zh" ]; then
        cat <<'EOF'
用法:
  springboot module list --name=<项目名> --type=<maven|gradle> [选项]

选项:
  --name=<值>                  目标项目名
  --type=<值>                  构建工具：maven | gradle（默认 maven）
  --module-path=<值>           Maven 父模块路径（默认项目根）
  --help, -h                   显示帮助信息并退出
  --zh                         使用中文输出
EOF
        return 0
    fi
    cat <<'EOF'
Usage:
  springboot module list --name=<project-name> --type=<maven|gradle> [options]

Options:
  --name=<value>               Target project name
  --type=<value>               Build tool: maven | gradle (default maven)
  --module-path=<value>        Maven parent module path (default: project root)
  --help, -h                   Show help and exit
  --zh                         Print messages in Chinese
EOF
}

print_help_module_remove() {
    if [ "${OUTPUT_LANG}" = "zh" ]; then
        cat <<'EOF'
用法:
  springboot module remove --name=<项目名> --type=<maven|gradle> --module=<子模块名> [选项]

选项:
  --name=<值>                  目标项目名
  --module=<值>                待移除子模块名
  --type=<值>                  构建工具：maven | gradle（默认 maven）
  --module-path=<值>           父模块路径（默认项目根）
  --dry-run                    仅打印执行计划，不修改文件
  --help, -h                   显示帮助信息并退出
  --zh                         使用中文输出
EOF
        return 0
    fi
    cat <<'EOF'
Usage:
  springboot module remove --name=<project-name> --type=<maven|gradle> --module=<module-name> [options]

Options:
  --name=<value>               Target project name
  --module=<value>             Module name to remove
  --type=<value>               Build tool: maven | gradle (default maven)
  --module-path=<value>        Parent module path (default: project root)
  --dry-run                    Print the execution plan only; do not modify files
  --help, -h                   Show help and exit
  --zh                         Print messages in Chinese
EOF
}

print_help_deps() {
    if [ "${OUTPUT_LANG}" = "zh" ]; then
        cat <<'EOF'
用法:
  springboot deps <subcommand> [options]

子命令:
  list              查看依赖列表（终端或网页）
  preview           输出依赖声明片段（Maven/Gradle）
  search            按关键词搜索依赖 ID

选项:
  --help, -h        显示帮助信息并退出
  --zh              使用中文输出

示例:
  springboot deps list --boot=3.5.14 --output=terminal
  springboot deps list --boot=3.5.14 --output=web
  springboot deps preview --type=gradle --deps=web,data-jpa --boot=3.5.14
EOF
        return 0
    fi
    cat <<'EOF'
Usage:
  springboot deps <subcommand> [options]

Subcommands:
  list              Show the dependency list (terminal or web)
  preview           Print dependency declaration snippets (Maven/Gradle)
  search            Search dependency IDs by keyword

Options:
  --help, -h        Show help and exit
  --zh              Print messages in Chinese

Examples:
  springboot deps list --boot=3.5.14 --output=terminal
  springboot deps list --boot=3.5.14 --output=web
  springboot deps preview --type=gradle --deps=web,data-jpa --boot=3.5.14
EOF
}

print_help_deps_list() {
    if [ "${OUTPUT_LANG}" = "zh" ]; then
        cat <<'EOF'
用法:
  springboot deps list [选项]

说明:
  查看指定 Boot 版本可用依赖列表（缓存到 deps-cache/）。

选项:
  --boot=<值>                  Spring Boot 版本（默认取当前 Initializr 默认版本，可用 springboot boot list 查看）
  --output=<值>                输出方式：terminal | web（默认 terminal）
  --refresh                    强制刷新缓存
  --help, -h                   显示本命令帮助并退出
  --zh                         使用中文输出

相关环境变量:
  INITIALIZR_BASE_URL=<url>      覆盖 Spring Initializr 基础地址（默认 https://start.spring.io）
  DEPS_CACHE_TTL_SECONDS=<秒>      依赖缓存过期秒数（默认 86400）

示例:
  springboot deps list
  springboot deps list --boot=3.5.14 --output=terminal
  springboot deps list --boot=3.5.14 --output=web
EOF
        return 0
    fi
    cat <<'EOF'
Usage:
  springboot deps list [options]

Description:
  Show dependencies available for a Boot version (cached under deps-cache/).

Options:
  --boot=<value>               Spring Boot version (default: current Initializr default; see springboot boot list)
  --output=<value>             Output: terminal | web (default terminal)
  --refresh                    Force a cache refresh
  --help, -h                   Show this command's help and exit
  --zh                         Print messages in Chinese

Related environment variables:
  INITIALIZR_BASE_URL=<url>      Override the Spring Initializr base URL (default https://start.spring.io)
  DEPS_CACHE_TTL_SECONDS=<seconds> Dependency cache TTL in seconds (default 86400)

Examples:
  springboot deps list
  springboot deps list --boot=3.5.14 --output=terminal
  springboot deps list --boot=3.5.14 --output=web
EOF
}

print_help_deps_preview() {
    if [ "${OUTPUT_LANG}" = "zh" ]; then
        cat <<'EOF'
用法:
  springboot deps preview --deps=<依赖ID列表> [选项]

说明:
  仅输出依赖声明片段，不创建项目。
  - maven: 输出 pom.xml 的 <dependencies> 内部内容
  - gradle: 输出 build.gradle 的 dependencies { } 内部内容

必填:
  --deps=<值>                  依赖ID列表（逗号分隔）

选项:
  --type=<值>                  构建工具：maven | gradle（默认 maven）
  --language=<值>              代码语言：java | kotlin | groovy（默认 java）
  --gradle-dsl=<值>            Gradle DSL：groovy | kotlin（默认 groovy）
  --boot=<值>                  Spring Boot 版本（默认取当前 Initializr 默认版本，可用 springboot boot list 查看）
  --java=<值>                  Java 版本：17 | 21 | 25（默认 17）
  --help, -h                   显示本命令帮助并退出
  --zh                         使用中文输出

相关环境变量:
  INITIALIZR_BASE_URL=<url>      覆盖 Spring Initializr 基础地址（默认 https://start.spring.io）

示例:
  springboot deps preview --deps=web,data-jpa
  springboot deps preview --type=gradle --deps=web,data-jpa,mysql --boot=3.5.14
EOF
        return 0
    fi
    cat <<'EOF'
Usage:
  springboot deps preview --deps=<dependency-ids> [options]

Description:
  Print dependency declaration snippets only. No project is created.
  - maven: contents inside <dependencies> in pom.xml
  - gradle: contents inside dependencies { } in build.gradle

Required:
  --deps=<value>               Dependency IDs, comma-separated

Options:
  --type=<value>               Build tool: maven | gradle (default maven)
  --language=<value>           Language: java | kotlin | groovy (default java)
  --gradle-dsl=<value>         Gradle DSL: groovy | kotlin (default groovy)
  --boot=<value>               Spring Boot version (default: current Initializr default; see springboot boot list)
  --java=<value>               Java version: 17 | 21 | 25 (default 17)
  --help, -h                   Show this command's help and exit
  --zh                         Print messages in Chinese

Related environment variables:
  INITIALIZR_BASE_URL=<url>      Override the Spring Initializr base URL (default https://start.spring.io)

Examples:
  springboot deps preview --deps=web,data-jpa
  springboot deps preview --type=gradle --deps=web,data-jpa,mysql --boot=3.5.14
EOF
}

print_help_deps_search() {
    if [ "${OUTPUT_LANG}" = "zh" ]; then
        cat <<'EOF'
用法:
  springboot deps search --query=<关键词> [选项]

选项:
  --query=<值>                 搜索关键词（匹配 ID / 名称 / 描述）
  --boot=<值>                  Spring Boot 版本（默认取当前 Initializr 默认版本，可用 springboot boot list 查看）
  --help, -h                   显示帮助信息并退出
  --zh                         使用中文输出

相关环境变量:
  INITIALIZR_BASE_URL=<url>      覆盖 Spring Initializr 基础地址（默认 https://start.spring.io）
  DEPS_CACHE_TTL_SECONDS=<秒>      依赖缓存过期秒数（默认 86400）
EOF
        return 0
    fi
    cat <<'EOF'
Usage:
  springboot deps search --query=<keyword> [options]

Options:
  --query=<value>              Search keyword (matches ID / name / description)
  --boot=<value>               Spring Boot version (default: current Initializr default; see springboot boot list)
  --help, -h                   Show help and exit
  --zh                         Print messages in Chinese

Related environment variables:
  INITIALIZR_BASE_URL=<url>      Override the Spring Initializr base URL (default https://start.spring.io)
  DEPS_CACHE_TTL_SECONDS=<seconds> Dependency cache TTL in seconds (default 86400)
EOF
}
