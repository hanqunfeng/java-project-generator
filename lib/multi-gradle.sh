#!/usr/bin/env bash
# ========= 多模块 Gradle 项目（multi）=========
# 本脚本由入口脚本 springboot 通过 source 加载，直接使用其已解析的变量：
#   projectName, bootVersion, groupId, artifactId, description,
#   javaVersion, packageName, subModules, configFormat, action, addModuleName,
#   projectVersion, modulePackaging, modulePath

source "${SCRIPT_DIR}/lib/nested-common.sh"
source "${SCRIPT_DIR}/lib/module-template-common.sh"
source "${SCRIPT_DIR}/lib/project-common.sh"

# 统一退出码（来源入口脚本，缺失时使用默认值）。
exit_param="${EXIT_PARAM:-1}"
exit_fs="${EXIT_FS:-3}"
exit_dep="${EXIT_DEP:-4}"
# 可通过环境变量覆盖 dependency-management 插件版本。
gradle_dm_plugin_version="${GRADLE_DM_PLUGIN_VERSION:-1.1.7}"
gradle_dsl="${gradleDsl:-groovy}"
root_settings_file="settings.gradle"
root_build_file="build.gradle"
module_build_file="build.gradle"
if [[ "$gradle_dsl" == "kotlin" ]]; then
    root_settings_file="settings.gradle.kts"
    root_build_file="build.gradle.kts"
    module_build_file="build.gradle.kts"
fi

GRADLE_DEPS_CACHE_KEY=""
GRADLE_DEPS_CACHE_VALUE=""

# -----------------------------------------------------------------------------
# 函数: escape_gradle_single_quoted
# 作用: 对写入单引号字符串的内容做 Gradle 安全转义。
# 入参:
#   $1 -> 原始文本
# 返回:
#   stdout -> 转义后文本
# -----------------------------------------------------------------------------
escape_gradle_single_quoted() {
    local text="$1"
    text=${text//\\/\\\\}
    text=${text//\'/\\\'}
    printf '%s' "$text"
}

# -----------------------------------------------------------------------------
# 函数: resolve_gradle_target_parent
# 作用: add-module 场景解析父模块路径并校验根 settings.gradle。
# -----------------------------------------------------------------------------
resolve_gradle_target_parent() {
    resolve_parent_dir_common
    rootSettingsFile="${projectName}/${root_settings_file}"
    if [ ! -f "$rootSettingsFile" ] && [ -f "${projectName}/settings.gradle" ]; then
        rootSettingsFile="${projectName}/settings.gradle"
        root_settings_file="settings.gradle"
        gradle_dsl="groovy"
    fi
    if [ ! -f "$rootSettingsFile" ] && [ -f "${projectName}/settings.gradle.kts" ]; then
        rootSettingsFile="${projectName}/settings.gradle.kts"
        root_settings_file="settings.gradle.kts"
        root_build_file="build.gradle.kts"
        module_build_file="build.gradle.kts"
        gradle_dsl="kotlin"
    fi

    ensure_dir_exists_common "$targetParentDir" "父模块目录不存在"
    ensure_file_exists_common "$rootSettingsFile" "settings.gradle 不存在"
}

# -----------------------------------------------------------------------------
# 函数: resolve_gradle_dependencies_block
# 作用: 获取 Gradle dependencies 内部片段并做进程内缓存，避免重复联网请求。
# 入参:
#   $1 -> 依赖 CSV（如 web,data-jpa）
# 返回:
#   stdout -> 依赖声明片段（不含 dependencies { } 包裹）
# -----------------------------------------------------------------------------
resolve_gradle_dependencies_block() {
    local depsCsv="$1"
    if [ -z "$depsCsv" ]; then
        depsCsv="${DEFAULT_DEPS:-web,devtools}"
    fi

    if [[ "$depsCsv" == "${DEFAULT_DEPS:-web,devtools}" ]]; then
        if [[ "$gradle_dsl" == "kotlin" ]]; then
            printf '%s\n' '    implementation("org.springframework.boot:spring-boot-starter-web")
    developmentOnly("org.springframework.boot:spring-boot-devtools")
    testImplementation("org.springframework.boot:spring-boot-starter-test")'
        else
            printf '%s\n' "    implementation 'org.springframework.boot:spring-boot-starter-web'
    developmentOnly 'org.springframework.boot:spring-boot-devtools'
    testImplementation 'org.springframework.boot:spring-boot-starter-test'"
        fi
        return 0
    fi

    if [[ "$GRADLE_DEPS_CACHE_KEY" != "$depsCsv" || -z "$GRADLE_DEPS_CACHE_VALUE" ]]; then
        if declare -f extract_dependencies_declaration_block >/dev/null 2>&1; then
            GRADLE_DEPS_CACHE_VALUE="$(extract_dependencies_declaration_block "$depsCsv" "gradle")" || exit "$exit_dep"
        else
            echo "当前执行上下文缺少依赖声明提取函数，无法根据 --deps 生成 Gradle 依赖块"
            exit "$exit_dep"
        fi
        GRADLE_DEPS_CACHE_KEY="$depsCsv"
    fi

    printf '%s\n' "$GRADLE_DEPS_CACHE_VALUE"
}

# -----------------------------------------------------------------------------
# 函数: print_gradle_module_plan
# 作用: dry-run 输出单个 Gradle 模块的预计创建/挂载动作。
# -----------------------------------------------------------------------------
print_gradle_module_plan() {
    local mod="$1"
    local modDir="$2"
    local modulePkg="$3"
    local includePath="$4"
    local depsCsv="$5"

    if [[ "$modulePkg" == "jar" ]]; then
        print_jar_module_scaffold_plan_common "${modDir}" "${packageName}" "${mod}" "${configFormat}"
        plan_echo "WRITE" "写入子模块依赖: '${modDir}/${module_build_file}' <- --deps=${depsCsv}"
        plan_echo "WRITE" "生成子模块构建文件: '${modDir}/${module_build_file}' (packaging=jar, bootVersion=${bootVersion}, javaVersion=${javaVersion}, dependencyManagementVersion=${gradle_dm_plugin_version})"
    else
        plan_echo "WRITE" "创建聚合模块目录: '${modDir}' (packaging=pom 映射为聚合模块，不生成 src 与依赖)"
        plan_echo "FLOW" "module-packaging=pom 时忽略 --deps=${depsCsv}"
        plan_echo "WRITE" "生成聚合模块构建文件: '${modDir}/${module_build_file}' (不应用 java/spring-boot 插件)"
    fi
    plan_echo "WRITE" "更新根 ${root_settings_file}: '${projectName}/${root_settings_file}'，追加 include '${includePath}'"
}

# -----------------------------------------------------------------------------
# 函数: print_gradle_plan
# 作用: dry-run 输出 Gradle create / add-module 全流程计划。
# -----------------------------------------------------------------------------
print_gradle_plan() {
    if [[ "$action" == "add-module" ]]; then
        local mod="${addModuleName}"
        local parentDirForPlan="${projectName}"
        if [ -n "$modulePath" ]; then
            parentDirForPlan="${projectName}/${modulePath}"
        fi
        local modDir="${parentDirForPlan}/${mod}"
        local includePath
        includePath=$(build_gradle_include_path_common "$modulePath" "$mod")
        plan_echo "CHECK" "解析父模块路径: '${modulePath:-<项目根>}' -> '${parentDirForPlan}'"
        plan_echo "CHECK" "检查根 ${root_settings_file} 存在: '${projectName}/${root_settings_file}'"
        plan_echo "CHECK" "检查子模块目录不存在: '${modDir}'"
        print_gradle_module_plan "$mod" "$modDir" "${modulePackaging}" "$includePath" "${dependencies}"
        plan_echo "CHECK" "若 settings.gradle 中已包含 '${includePath}'，则终止并提示冲突"
        plan_echo "FLOW" "输出完成提示: Gradle 子模块追加完成: ${mod}"
    else
        plan_echo "WRITE" "创建父项目目录: '${projectName}'"
        plan_echo "WRITE" "生成项目忽略文件: '${projectName}/.gitignore'"
        if [ -n "$subModules" ]; then
            plan_echo "FLOW" "根据 modules 参数构建 settings.gradle include 列表: '${subModules}'"
        else
            plan_echo "FLOW" "未提供 modules 参数，${root_settings_file} 仅包含 rootProject.name"
        fi
        plan_echo "WRITE" "生成 ${root_settings_file}: '${projectName}/${root_settings_file}'"
        plan_echo "WRITE" "生成根 ${root_build_file}: '${projectName}/${root_build_file}' (group=${groupId}, version=${projectVersion})"
        if [ -n "$subModules" ]; then
            while IFS= read -r mod; do
                [ -z "$mod" ] && continue
                print_gradle_module_plan "$mod" "${projectName}/${mod}" "jar" ":${mod}" "${dependencies}"
            done < <(iterate_csv_items_common "$subModules")
        fi
        plan_echo "FLOW" "输出完成提示: Gradle 多模块项目创建完成"
    fi
}

# -----------------------------------------------------------------------------
# 函数: create_gradle_module
# 作用: 实际创建 Gradle 子模块构建脚本、目录骨架与源码模板。
# 入参:
#   $1 -> moduleName
#   $2 -> moduleDir
#   $3 -> modulePackaging（可选，默认 jar）
#   $4 -> 依赖 CSV（可选，默认读取全局 dependencies）
# -----------------------------------------------------------------------------
create_gradle_module() {
    local mod="$1"
    local modDir="$2"
    local modulePkg="${3:-jar}"
    local depsCsv="${4:-${dependencies:-${DEFAULT_DEPS:-web,devtools}}}"
    local depsBlock=""
    local escapedBootVersion escapedDmVersion source_language
    escapedBootVersion="$(escape_gradle_single_quoted "$bootVersion")"
    escapedDmVersion="$(escape_gradle_single_quoted "$gradle_dm_plugin_version")"
    source_language="${projectLanguage:-java}"
    if [[ "$modulePkg" == "jar" ]]; then
        create_module_scaffold_common "${modDir}" "${packageName}" "${mod}" "${configFormat}" "${modulePkg}"
        depsBlock="$(resolve_gradle_dependencies_block "$depsCsv")"
        if [[ "$gradle_dsl" == "kotlin" ]]; then
            cat > "${modDir}/${module_build_file}" <<EOF
plugins {
    ${source_language:+id("${source_language}")}
    id("org.springframework.boot") version "${escapedBootVersion}"
    id("io.spring.dependency-management") version "${escapedDmVersion}"
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(${javaVersion}))
    }
}

dependencies {
${depsBlock}
}

tasks.withType<Test> {
    useJUnitPlatform()
}
EOF
        else
            # 生成子模块 build.gradle
            cat > "${modDir}/${module_build_file}" <<EOF
plugins {
    id '${source_language}'
    id 'org.springframework.boot' version '${escapedBootVersion}'
    id 'io.spring.dependency-management' version '${escapedDmVersion}'
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(${javaVersion})
    }
}

dependencies {
${depsBlock}
}

test {
    useJUnitPlatform()
}
EOF
        fi
        write_module_application_files "$mod" "$modDir"
    else
        create_module_scaffold_common "${modDir}" "${packageName}" "${mod}" "${configFormat}" "${modulePkg}"
        cat > "${modDir}/${module_build_file}" <<EOF
// Aggregator module mapped from module-packaging=pom.
// Intentionally no java/spring-boot plugin and no dependencies.
EOF
    fi

    if [[ "$modulePkg" == "jar" ]]; then
        echo "  已创建子模块: ${mod} (packaging=${modulePkg}, deps=${depsCsv})"
    else
        echo "  已创建子模块: ${mod} (packaging=${modulePkg}, deps=ignored)"
    fi
}

# -----------------------------------------------------------------------------
# 函数: ensure_settings_include_absent
# 作用: 校验 settings.gradle 中尚未包含目标 include 行。
# 入参:
#   $1 -> includePath（如 :platform:api）
# -----------------------------------------------------------------------------
ensure_settings_include_absent() {
    local includePath="$1"
    local settingsFile="${projectName}/${root_settings_file}"
    local settingsContent
    local includeLine="include '${includePath}'"
    if [[ "$gradle_dsl" == "kotlin" ]]; then
        includeLine="include(\"${includePath}\")"
    fi

    if [ ! -f "$settingsFile" ]; then
        echo "settings.gradle 不存在: ${settingsFile}"
        exit "$exit_fs"
    fi

    settingsContent=$(<"$settingsFile")
    if [[ "$settingsContent" == *"$includeLine"* ]]; then
        echo "子模块已存在于 settings.gradle: ${includePath}"
        exit "$exit_param"
    fi
}

# -----------------------------------------------------------------------------
# 函数: append_module_to_settings_gradle
# 作用: 把 includePath 追加到根 settings.gradle。
# 入参:
#   $1 -> includePath（如 :platform:api）
# 前置条件:
#   调用前已通过 ensure_settings_include_absent 完成重复校验
# -----------------------------------------------------------------------------
append_module_to_settings_gradle() {
    local includePath="$1"
    local settingsFile="${projectName}/${root_settings_file}"
    local includeLine="include '${includePath}'"
    if [[ "$gradle_dsl" == "kotlin" ]]; then
        includeLine="include(\"${includePath}\")"
    fi

    if [ ! -f "$settingsFile" ]; then
        echo "settings.gradle 不存在: ${settingsFile}"
        exit "$exit_fs"
    fi

    echo "$includeLine" >> "$settingsFile"
}

if [[ "${dryRun:-false}" == "true" ]]; then
    print_gradle_plan
    return 0
fi

if [[ "$action" == "add-module" ]]; then
    mod="${addModuleName}"
    resolve_gradle_target_parent
    modDir="$(build_module_dir_common "$mod")"
    includePath=$(build_gradle_include_path_common "$modulePath" "$mod")
    ensure_module_dir_absent_common "$modDir"

    ensure_settings_include_absent "$includePath"
    create_gradle_module "$mod" "$modDir" "${modulePackaging}" "${dependencies}"
    append_module_to_settings_gradle "$includePath"
    echo "Gradle 子模块追加完成: ${mod} (父模块路径: ${modulePath:-<项目根>}, packaging=${modulePackaging})"
else
    escapedProjectName="$(escape_gradle_single_quoted "$projectName")"
    escapedGroupId="$(escape_gradle_single_quoted "$groupId")"
    escapedProjectVersion="$(escape_gradle_single_quoted "$projectVersion")"
    # 创建父项目目录
    mkdir -p "${projectName}"
    write_project_gitignore "${projectName}"

    # 构建 settings.gradle 的 include 块
    includesGradle=""
    if [ -n "$subModules" ]; then
        while IFS= read -r mod; do
            [ -z "$mod" ] && continue
            if [[ "$gradle_dsl" == "kotlin" ]]; then
                includesGradle+="include(\":${mod}\")"$'\n'
            else
                includesGradle+="include ':${mod}'"$'\n'
            fi
        done < <(iterate_csv_items_common "$subModules")
    fi

    # 生成 settings.gradle
    if [[ "$gradle_dsl" == "kotlin" ]]; then
        cat > "${projectName}/${root_settings_file}" <<EOF
rootProject.name = "${escapedProjectName}"
${includesGradle}
EOF
    else
        cat > "${projectName}/${root_settings_file}" <<EOF
rootProject.name = '${escapedProjectName}'
${includesGradle}
EOF
    fi

    # 生成根 build.gradle
    if [[ "$gradle_dsl" == "kotlin" ]]; then
        cat > "${projectName}/${root_build_file}" <<EOF
allprojects {
    group = "${escapedGroupId}"
    version = "${escapedProjectVersion}"

    repositories {
        mavenCentral()
    }
}
EOF
    else
        cat > "${projectName}/${root_build_file}" <<EOF
allprojects {
    group = '${escapedGroupId}'
    version = '${escapedProjectVersion}'

    repositories {
        mavenCentral()
    }
}
EOF
    fi

    # 生成子模块
    if [ -n "$subModules" ]; then
        while IFS= read -r mod; do
            [ -z "$mod" ] && continue
            create_gradle_module "$mod" "${projectName}/${mod}" "jar" "${dependencies}"
        done < <(iterate_csv_items_common "$subModules")
    fi
    echo "Gradle 多模块项目创建完成"
fi
