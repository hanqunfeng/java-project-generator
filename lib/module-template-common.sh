#!/usr/bin/env bash
# ========= 模块模板公共逻辑 =========

# -----------------------------------------------------------------------------
# 函数: build_package_subpath_common
# 作用: 把 Java 包名 + 模块名映射为源码目录子路径。
# 示例:
#   com.example + order-api -> com/example/order_api
# 入参:
#   $1 -> packageName
#   $2 -> moduleName
# 返回:
#   stdout -> 包路径 + 模块名子路径（模块名 '-' 会转为 '_'）
# -----------------------------------------------------------------------------
build_package_subpath_common() {
    local packageName="$1"
    local mod="$2"
    local packagePath
    packagePath="$(echo "${packageName}" | tr '.' '/')"
    printf '%s/%s\n' "${packagePath}" "${mod//-/_}"
}

# -----------------------------------------------------------------------------
# 函数: module_class_name
# 作用: 把模块名转换为 Application 类名（PascalCase + Application）。
# 入参:
#   $1 -> moduleName（如 order-api / user_service）
# 返回:
#   stdout -> 类名（如 OrderApiApplication / UserServiceApplication）
# -----------------------------------------------------------------------------
module_class_name() {
    local mod="$1"
    local part
    local result=""
    IFS='-_'
    for part in $mod; do
        [ -z "$part" ] && continue
        result+="${part^}"
    done
    unset IFS
    printf '%sApplication' "$result"
}

# -----------------------------------------------------------------------------
# 函数: write_module_application_files
# 作用: 为 jar 子模块生成最小可运行的启动类与测试类。
# 入参:
#   $1 -> moduleName
#   $2 -> moduleDir
#   $3 -> packageName（可选；省略时回退全局 packageName）
# 返回:
#   0 -> 写入成功
#   1 -> 无可用 packageName
# -----------------------------------------------------------------------------
write_module_application_files() {
    local mod="$1"
    local modDir="$2"
    local packageNameArg="${3:-${packageName:-}}"
    local packagePath
    local packageDecl
    local className
    local basePath
    local testClassName

    if [ -z "$packageNameArg" ]; then
        echo "write_module_application_files 需要 packageName 参数"
        return 1
    fi

    packagePath="$(build_package_subpath_common "${packageNameArg}" "${mod}")"
    packageDecl="${packageNameArg}.$(printf '%s' "$mod" | tr '-' '_')"
    className="$(module_class_name "$mod")"
    testClassName="${className}Tests"
    basePath="${modDir}/src/main/java/${packagePath}"
    mkdir -p "$basePath" "${modDir}/src/test/java/${packagePath}"

    cat > "${basePath}/${className}.java" <<EOF
package ${packageDecl};

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ${className} {
    public static void main(String[] args) {
        SpringApplication.run(${className}.class, args);
    }
}
EOF

    cat > "${modDir}/src/test/java/${packagePath}/${testClassName}.java" <<EOF
package ${packageDecl};

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class ${testClassName} {

    @Test
    void contextLoads() {
    }
}
EOF
}

# -----------------------------------------------------------------------------
# 函数: create_module_scaffold_common
# 作用: 创建模块基础目录结构与配置文件。
# 规则:
#   - jar: 生成 src/main/src/test 与 application 配置文件
#   - 非 jar（如 pom 聚合模块）: 仅创建模块目录
# 入参:
#   $1 -> 模块目录
#   $2 -> packageName
#   $3 -> moduleName
#   $4 -> 配置格式（properties|yaml）
#   $5 -> modulePackaging（jar|pom）
# -----------------------------------------------------------------------------
create_module_scaffold_common() {
    local modDir="$1"
    local packageName="$2"
    local mod="$3"
    local configFormat="$4"
    local modulePackaging="$5"
    local subpath

    if [[ "$modulePackaging" != "jar" ]]; then
        mkdir -p "${modDir}"
        return 0
    fi

    subpath="$(build_package_subpath_common "${packageName}" "${mod}")"
    mkdir -p "${modDir}/src/main/java/${subpath}"
    mkdir -p "${modDir}/src/main/resources"
    mkdir -p "${modDir}/src/test/java/${subpath}"

    # 生成最小默认配置，避免产物为空文件。
    if [[ "$configFormat" == "yaml" ]]; then
        printf 'spring:\n  application:\n    name: %s\n' "${mod}" > "${modDir}/src/main/resources/application.yaml"
    else
        printf 'spring.application.name=%s\n' "${mod}" > "${modDir}/src/main/resources/application.properties"
    fi
}

# -----------------------------------------------------------------------------
# 函数: print_jar_module_scaffold_plan_common
# 作用: dry-run 输出 jar 子模块通用目录/配置/模板计划。
# 入参:
#   $1 -> 模块目录
#   $2 -> packageName
#   $3 -> moduleName
#   $4 -> 配置格式（properties|yaml）
# 依赖:
#   plan_echo（由入口脚本提供）
# -----------------------------------------------------------------------------
print_jar_module_scaffold_plan_common() {
    local modDir="$1"
    local packageNameArg="$2"
    local mod="$3"
    local configFormatArg="$4"
    local packageSubpath

    packageSubpath="$(build_package_subpath_common "${packageNameArg}" "${mod}")"
    plan_echo "WRITE" "创建子模块目录结构: '${modDir}/src/main/java/${packageSubpath}'"
    plan_echo "WRITE" "创建子模块目录结构: '${modDir}/src/main/resources'"
    plan_echo "WRITE" "创建子模块目录结构: '${modDir}/src/test/java/${packageSubpath}'"
    plan_echo "WRITE" "生成 Spring Boot 启动类与测试类: '${modDir}/src/main/java/.../*Application.java' 和 '${modDir}/src/test/java/.../*ApplicationTests.java'"
    if [[ "$configFormatArg" == "yaml" ]]; then
        plan_echo "WRITE" "创建配置文件: '${modDir}/src/main/resources/application.yaml' (if configFormat=yaml)"
    else
        plan_echo "WRITE" "创建配置文件: '${modDir}/src/main/resources/application.properties' (if configFormat=properties)"
    fi
}
