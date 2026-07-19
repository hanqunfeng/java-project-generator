#!/usr/bin/env bash
# ========= 多模块 Maven 项目（pom）=========
# 本脚本由入口脚本 springboot 通过 source 加载，直接使用其已解析的变量：
#   projectName, bootVersion, groupId, artifactId, description,
#   javaVersion, packageName, subModules, configFormat, action, addModuleName,
#   parentVersion, projectVersion, modulePackaging, modulePath

source "${SCRIPT_DIR}/lib/nested-common.sh"
source "${SCRIPT_DIR}/lib/module-template-common.sh"
source "${SCRIPT_DIR}/lib/project-common.sh"

LAST_COORDINATE_PARSER=""
EXTRACTED_COORDINATE=""
# 统一退出码（来源入口脚本，缺失时使用默认值）。
exit_param="${EXIT_PARAM:-1}"
exit_fs="${EXIT_FS:-3}"
exit_dep="${EXIT_DEP:-4}"

# -----------------------------------------------------------------------------
# 函数: xml_escape
# 作用: 对 XML 模板中的动态文本做实体转义。
# 入参:
#   $1 -> 原始文本
# 返回:
#   stdout -> XML 安全文本
# -----------------------------------------------------------------------------
xml_escape() {
    local text="$1"
    text=${text//&/&amp;}
    text=${text//</&lt;}
    text=${text//>/&gt;}
    text=${text//\"/&quot;}
    text=${text//\'/&apos;}
    printf '%s' "$text"
}

# -----------------------------------------------------------------------------
# 函数: extract_coordinate_by_maven
# 作用: 通过 mvn help:evaluate 解析 POM 坐标（最高优先级）。
# 入参:
#   $1 -> tag（groupId/artifactId/version/packaging）
#   $2 -> pom 文件路径
# 返回:
#   stdout -> 解析值；失败返回非 0
# -----------------------------------------------------------------------------
extract_coordinate_by_maven() {
    local tag="$1"
    local pomFile="$2"
    local expression
    local rawOutput
    local value

    if ! command -v mvn >/dev/null 2>&1; then
        return 1
    fi

    case "$tag" in
        groupId) expression="project.groupId" ;;
        artifactId) expression="project.artifactId" ;;
        version) expression="project.version" ;;
        packaging) expression="project.packaging" ;;
        *) return 1 ;;
    esac

    rawOutput=$(mvn -q -f "$pomFile" -DforceStdout help:evaluate -Dexpression="$expression" 2>/dev/null)
    value=$(printf '%s\n' "$rawOutput" | awk '
        /^[[:space:]]*$/ { next }
        /^\[/ { next }
        /^Download/ { next }
        /^Progress/ { next }
        { line=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", line); last=line }
        END { print last }
    ')

    if [ -n "$value" ] && [[ "$value" != *'$'* ]]; then
        printf '%s\n' "$value"
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# 函数: extract_coordinate_by_xmllint
# 作用: 通过 xmllint + xpath 解析 POM 坐标（第一回退）。
# -----------------------------------------------------------------------------
extract_coordinate_by_xmllint() {
    local tag="$1"
    local pomFile="$2"
    local value
    local xpath

    if ! command -v xmllint >/dev/null 2>&1; then
        return 1
    fi

    xpath="string((/*[local-name()='project']/*[local-name()='${tag}'])[1])"
    value=$(xmllint --xpath "$xpath" "$pomFile" 2>/dev/null)
    value=$(printf '%s' "$value" | awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print }')

    if [ -z "$value" ] && [[ "$tag" == "groupId" || "$tag" == "version" ]]; then
        xpath="string((/*[local-name()='project']/*[local-name()='parent']/*[local-name()='${tag}'])[1])"
        value=$(xmllint --xpath "$xpath" "$pomFile" 2>/dev/null)
        value=$(printf '%s' "$value" | awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print }')
    fi

    if [ -n "$value" ]; then
        printf '%s\n' "$value"
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# 函数: extract_coordinate_by_xmlstarlet
# 作用: 通过 xmlstarlet 解析 POM 坐标（第二回退）。
# -----------------------------------------------------------------------------
extract_coordinate_by_xmlstarlet() {
    local tag="$1"
    local pomFile="$2"
    local value
    local xpath

    if ! command -v xmlstarlet >/dev/null 2>&1; then
        return 1
    fi

    xpath="/*[local-name()='project']/*[local-name()='${tag}'][1]"
    value=$(xmlstarlet sel -t -v "$xpath" -n "$pomFile" 2>/dev/null | awk 'NF{print; exit}')

    if [ -z "$value" ] && [[ "$tag" == "groupId" || "$tag" == "version" ]]; then
        xpath="/*[local-name()='project']/*[local-name()='parent']/*[local-name()='${tag}'][1]"
        value=$(xmlstarlet sel -t -v "$xpath" -n "$pomFile" 2>/dev/null | awk 'NF{print; exit}')
    fi

    if [ -n "$value" ]; then
        printf '%s\n' "$value"
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# 函数: extract_coordinate_by_awk
# 作用: 纯文本兜底解析 POM 坐标（最后回退）。
# -----------------------------------------------------------------------------
extract_coordinate_by_awk() {
    local tag="$1"
    local pomFile="$2"

    awk -v tag="$tag" '
        /<parent>/ { in_parent=1 }
        in_parent && /<\/parent>/ { in_parent=0; next }
        in_parent { next }
        {
            line=$0
            if (!capturing) {
                openTag="<" tag ">"
                if (match(line, openTag)) {
                    line=substr(line, RSTART + RLENGTH)
                    capturing=1
                } else {
                    next
                }
            }

            closeTag="</" tag ">"
            if (match(line, closeTag)) {
                value=value substr(line, 1, RSTART - 1)
                gsub(/[[:space:]]+/, " ", value)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                print value
                exit
            }

            value=value line " "
        }
    ' "$pomFile"
}

# -----------------------------------------------------------------------------
# 函数: extract_project_coordinate
# 作用: 坐标统一解析入口，按工具可用性自动回退。
# 回退链:
#   mvn -> xmllint -> xmlstarlet -> awk
# 输出:
#   EXTRACTED_COORDINATE / LAST_COORDINATE_PARSER（全局变量）
# -----------------------------------------------------------------------------
extract_project_coordinate() {
    local tag="$1"
    local pomFile="$2"
    local value

    EXTRACTED_COORDINATE=""

    value=$(extract_coordinate_by_maven "$tag" "$pomFile")
    if [ -n "$value" ]; then
        LAST_COORDINATE_PARSER="mvn(help:evaluate)"
        EXTRACTED_COORDINATE="$value"
        return 0
    fi

    value=$(extract_coordinate_by_xmllint "$tag" "$pomFile")
    if [ -n "$value" ]; then
        LAST_COORDINATE_PARSER="xmllint(xpath)"
        EXTRACTED_COORDINATE="$value"
        return 0
    fi

    value=$(extract_coordinate_by_xmlstarlet "$tag" "$pomFile")
    if [ -n "$value" ]; then
        LAST_COORDINATE_PARSER="xmlstarlet(xpath)"
        EXTRACTED_COORDINATE="$value"
        return 0
    fi

    value=$(extract_coordinate_by_awk "$tag" "$pomFile")
    if [ -n "$value" ]; then
        LAST_COORDINATE_PARSER="awk(fallback)"
        EXTRACTED_COORDINATE="$value"
        return 0
    fi

    LAST_COORDINATE_PARSER="unresolved"
    return 1
}

# -----------------------------------------------------------------------------
# 函数: load_parent_coordinates
# 作用: 在 add-module 场景读取父 POM 的真实 GAV 坐标。
# 入参:
#   $1 -> 父 pom.xml 路径
# 副作用:
#   覆盖全局 groupId/artifactId/parentVersion
# -----------------------------------------------------------------------------
load_parent_coordinates() {
    local parentPom="$1"
    local detectedGroupId
    local detectedArtifactId
    local detectedVersion
    local parserGroupId="none"
    local parserArtifactId="none"
    local parserVersion="none"

    if [ -z "$parentPom" ] || [ ! -f "$parentPom" ]; then
        echo "父项目 pom.xml 不存在: ${parentPom}"
        exit "$exit_fs"
    fi

    extract_project_coordinate "groupId" "$parentPom"
    detectedGroupId="$EXTRACTED_COORDINATE"
    parserGroupId="$LAST_COORDINATE_PARSER"
    extract_project_coordinate "artifactId" "$parentPom"
    detectedArtifactId="$EXTRACTED_COORDINATE"
    parserArtifactId="$LAST_COORDINATE_PARSER"
    extract_project_coordinate "version" "$parentPom"
    detectedVersion="$EXTRACTED_COORDINATE"
    parserVersion="$LAST_COORDINATE_PARSER"

    if [ -z "$detectedGroupId" ] || [ -z "$detectedArtifactId" ] || [ -z "$detectedVersion" ]; then
        echo "无法从父 pom.xml 解析 groupId/artifactId/version: ${parentPom}"
        echo "解析详情: groupId='${detectedGroupId:-<空>}'(${parserGroupId}), artifactId='${detectedArtifactId:-<空>}'(${parserArtifactId}), version='${detectedVersion:-<空>}'(${parserVersion})"
        echo "已按顺序尝试: mvn(help:evaluate) -> xmllint(xpath) -> xmlstarlet(xpath) -> awk(fallback)"
        echo "排查建议: 1) 确认 pom.xml 格式合法 2) 安装 mvn 或 xmllint 3) 手工检查 groupId/artifactId/version 是否存在"
        exit "$exit_param"
    fi

    # add-module 场景强制使用父项目真实坐标，避免落回入口脚本默认值
    groupId="$detectedGroupId"
    artifactId="$detectedArtifactId"
    parentVersion="$detectedVersion"

    echo "父 POM 解析成功:"
    echo "  - groupId:    ${groupId}    [来源: ${parserGroupId}]"
    echo "  - artifactId: ${artifactId} [来源: ${parserArtifactId}]"
    echo "  - version:    ${parentVersion} [来源: ${parserVersion}]"
}

# -----------------------------------------------------------------------------
# 函数: resolve_target_parent_pom
# 作用: 解析并校验 add-module 的目标父模块。
# 校验:
#   1) 父目录存在
#   2) 父 pom.xml 存在
#   3) 父 packaging 为 pom
# -----------------------------------------------------------------------------
resolve_target_parent_pom() {
    resolve_parent_dir_common
    targetParentPom="${targetParentDir}/pom.xml"

    ensure_dir_exists_common "$targetParentDir" "父模块目录不存在"
    ensure_file_exists_common "$targetParentPom" "父模块 pom.xml 不存在"

    extract_project_coordinate "packaging" "$targetParentPom"
    targetParentPackaging="$EXTRACTED_COORDINATE"
    targetParentPackagingParser="$LAST_COORDINATE_PARSER"

    # Maven 默认 packaging 为 jar
    if [ -z "$targetParentPackaging" ]; then
        targetParentPackaging="jar"
        targetParentPackagingParser="default(jar)"
    fi

    if [ "$targetParentPackaging" != "pom" ]; then
        echo "父模块打包类型不支持追加子模块: ${targetParentPom}"
        echo "  - 当前 packaging: ${targetParentPackaging} [来源: ${targetParentPackagingParser}]"
        echo "  - 仅支持 packaging=pom 的聚合模块追加子模块"
        exit "$exit_param"
    fi
}

MAVEN_DEPS_CACHE_KEY=""
MAVEN_DEPS_CACHE_VALUE=""

# -----------------------------------------------------------------------------
# 函数: resolve_maven_dependencies_block
# 作用: 获取 Maven dependencies 内部片段并做进程内缓存，避免重复联网请求。
# 入参:
#   $1 -> 依赖 CSV（如 web,data-jpa）
# 返回:
#   stdout -> 依赖声明片段（不含 <dependencies> 包裹）
# -----------------------------------------------------------------------------
resolve_maven_dependencies_block() {
    local depsCsv="$1"
    if [ -z "$depsCsv" ]; then
        depsCsv="${DEFAULT_DEPS:-web,devtools}"
    fi

    if [[ "$depsCsv" == "${DEFAULT_DEPS:-web,devtools}" ]]; then
        printf '%s\n' '        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-devtools</artifactId>
            <scope>runtime</scope>
            <optional>true</optional>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>'
        return 0
    fi

    if [[ "$MAVEN_DEPS_CACHE_KEY" != "$depsCsv" || -z "$MAVEN_DEPS_CACHE_VALUE" ]]; then
        if declare -f extract_dependencies_declaration_block >/dev/null 2>&1; then
            MAVEN_DEPS_CACHE_VALUE="$(extract_dependencies_declaration_block "$depsCsv" "maven")" || exit "$exit_dep"
        else
            echo "当前执行上下文缺少依赖声明提取函数，无法根据 --deps 生成 Maven 依赖块"
            exit "$exit_dep"
        fi
        MAVEN_DEPS_CACHE_KEY="$depsCsv"
    fi

    printf '%s\n' "$MAVEN_DEPS_CACHE_VALUE"
}

# -----------------------------------------------------------------------------
# 函数: print_maven_module_plan
# 作用: dry-run 输出单个 Maven 模块的预计操作。
# -----------------------------------------------------------------------------
print_maven_module_plan() {
    local mod="$1"
    local modDir="$2"
    local modulePkg="$3"
    local parentInfo="$4"
    local depsCsv="$5"

    if [[ "$modulePkg" == "jar" ]]; then
        print_jar_module_scaffold_plan_common "${modDir}" "${packageName}" "${mod}" "${configFormat}"
        plan_echo "WRITE" "写入子模块依赖: '${modDir}/pom.xml' <- --deps=${depsCsv}"
    else
        plan_echo "WRITE" "创建聚合模块目录: '${modDir}' (packaging=pom, 不生成 src 与依赖)"
        plan_echo "FLOW" "module-packaging=pom 时忽略 --deps=${depsCsv}"
    fi
    plan_echo "WRITE" "生成子模块 POM: '${modDir}/pom.xml' (packaging=${modulePkg}, parent=${parentInfo}, artifactId=${mod})"
}

# -----------------------------------------------------------------------------
# 函数: print_maven_plan
# 作用: dry-run 输出 Maven create / add-module 全流程计划。
# -----------------------------------------------------------------------------
print_maven_plan() {
    if [[ "$action" == "add-module" ]]; then
        local mod="${addModuleName}"
        local targetParentDirForPlan="${projectName}"
        if [ -n "$modulePath" ]; then
            targetParentDirForPlan="${projectName}/${modulePath}"
        fi
        local targetParentPomForPlan="${targetParentDirForPlan}/pom.xml"
        local modDir="${targetParentDirForPlan}/${mod}"
        plan_echo "CHECK" "解析父模块路径: '${modulePath:-<项目根>}' -> '${targetParentDirForPlan}'"
        plan_echo "CHECK" "检查父模块 pom.xml 存在: '${targetParentPomForPlan}'"
        plan_echo "CHECK" "检查父模块 packaging 必须为 pom: '${targetParentPomForPlan}'"
        plan_echo "CHECK" "检查子模块目录不存在: '${modDir}'"
        plan_echo "CHECK" "读取父项目坐标: '${targetParentPomForPlan}' -> groupId/artifactId/version"
        plan_echo "CHECK" "校验父项目坐标解析成功，否则终止"
        print_maven_module_plan "$mod" "$modDir" "${modulePackaging}" "<从 ${targetParentPomForPlan} 解析的 groupId:artifactId:version>" "${dependencies}"
        plan_echo "WRITE" "更新父 POM: '${targetParentPomForPlan}'，在 <modules> 中追加 '<module>${mod}</module>'"
        plan_echo "CHECK" "若父 POM 已存在模块 '${mod}'，则终止并提示冲突（相对路径挂载）"
        plan_echo "FLOW" "输出完成提示: Maven 子模块追加完成: ${mod}"
    else
        # 子模块 parent.version 统一引用 ${revision}，与父 POM 的 CI-friendly 版本对齐
        parentVersion='${revision}'
        plan_echo "WRITE" "创建父项目目录: '${projectName}'"
        plan_echo "WRITE" "生成项目忽略文件: '${projectName}/.gitignore'"
        if [ -n "$subModules" ]; then
            plan_echo "FLOW" "根据 modules 参数构建父 POM 的 <modules> 列表: '${subModules}'"
        else
            plan_echo "FLOW" "未提供 modules 参数，父 POM 将不包含 <modules> 列表"
        fi
        plan_echo "WRITE" "生成父 POM 文件: '${projectName}/pom.xml' (packaging=pom, bootVersion=${bootVersion}, javaVersion=${javaVersion}, revision=${projectVersion})"
        if [ -n "$subModules" ]; then
            while IFS= read -r mod; do
                [ -z "$mod" ] && continue
                print_maven_module_plan "$mod" "${projectName}/${mod}" "jar" "${groupId}:${artifactId}:${parentVersion}" "${dependencies}"
            done < <(iterate_csv_items_common "$subModules")
        fi
        plan_echo "FLOW" "输出完成提示: Maven 多模块项目创建完成"
    fi
}

# -----------------------------------------------------------------------------
# 函数: create_maven_module
# 作用: 实际创建 Maven 子模块目录、POM 与模板源码。
# 入参:
#   $1 -> moduleName
#   $2 -> moduleDir
#   $3 -> modulePackaging（可选，默认 jar）
#   $4 -> 依赖 CSV（可选，默认读取全局 dependencies）
# -----------------------------------------------------------------------------
create_maven_module() {
    local mod="$1"
    local modDir="$2"
    local modulePkg="${3:-jar}"
    local depsCsv="${4:-${dependencies:-${DEFAULT_DEPS:-web,devtools}}}"
    local depsBlock=""
    local escapedGroupId escapedArtifactId escapedParentVersion escapedMod
    escapedGroupId="$(xml_escape "$groupId")"
    escapedArtifactId="$(xml_escape "$artifactId")"
    escapedParentVersion="$(xml_escape "$parentVersion")"
    escapedMod="$(xml_escape "$mod")"
    create_module_scaffold_common "${modDir}" "${packageName}" "${mod}" "${configFormat}" "${modulePkg}"

    # 生成子模块 pom.xml
    if [[ "$modulePkg" == "jar" ]]; then
        depsBlock="$(resolve_maven_dependencies_block "$depsCsv")"
        cat > "${modDir}/pom.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>${escapedGroupId}</groupId>
        <artifactId>${escapedArtifactId}</artifactId>
        <version>${escapedParentVersion}</version>
    </parent>

    <artifactId>${escapedMod}</artifactId>
    <packaging>${modulePkg}</packaging>
    <name>${escapedMod}</name>

    <dependencies>
${depsBlock}
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>

</project>
EOF
        write_module_application_files "$mod" "$modDir"
    else
        cat > "${modDir}/pom.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>${escapedGroupId}</groupId>
        <artifactId>${escapedArtifactId}</artifactId>
        <version>${escapedParentVersion}</version>
    </parent>

    <artifactId>${escapedMod}</artifactId>
    <packaging>${modulePkg}</packaging>
    <name>${escapedMod}</name>

</project>
EOF
    fi
    if [[ "$modulePkg" == "jar" ]]; then
        echo "  已创建子模块: ${mod} (packaging=${modulePkg}, deps=${depsCsv})"
    else
        echo "  已创建子模块: ${mod} (packaging=${modulePkg}, deps=ignored)"
    fi
}

# -----------------------------------------------------------------------------
# 函数: append_module_to_parent_pom
# 作用: 把子模块追加到父 POM 的 <modules> 中。
# 策略:
#   - 已有 <modules>：插入新 <module>
#   - 无 <modules>：自动注入 <modules> 块
# 入参:
#   $1 -> parentPom
#   $2 -> moduleEntry
# -----------------------------------------------------------------------------
append_module_to_parent_pom() {
    local parentPom="$1"
    local moduleEntry="$2"
    local parentContent
    local tmpFile

    if [ ! -f "$parentPom" ]; then
        echo "父项目 pom.xml 不存在: ${parentPom}"
        exit "$exit_fs"
    fi

    parentContent=$(<"$parentPom")
    if [[ "$parentContent" == *"<module>${moduleEntry}</module>"* ]]; then
        echo "子模块已存在于父 pom.xml: ${moduleEntry}"
        exit "$exit_param"
    fi

    tmpFile="${parentPom}.tmp"
    if [[ "$parentContent" == *"<modules>"* ]]; then
        awk -v mod="$moduleEntry" '
            /<\/modules>/ && !done {
                print "        <module>" mod "</module>"
                done=1
            }
            { print }
        ' "$parentPom" > "$tmpFile"
    else
        awk -v mod="$moduleEntry" '
            /<dependencyManagement>/ && !done {
                print "    <modules>"
                print "        <module>" mod "</module>"
                print "    </modules>"
                print ""
                done=1
            }
            { print }
        ' "$parentPom" > "$tmpFile"
        if ! grep -q "<modules>" "$tmpFile"; then
            awk -v mod="$moduleEntry" '
                /<\/project>/ && !done {
                    print "    <modules>"
                    print "        <module>" mod "</module>"
                    print "    </modules>"
                    print ""
                    done=1
                }
                { print }
            ' "$parentPom" > "$tmpFile"
        fi
    fi
    mv "$tmpFile" "$parentPom"
}

if [[ "${dryRun:-false}" == "true" ]]; then
    print_maven_plan
    return 0
fi

if [[ "$action" == "add-module" ]]; then
    mod="${addModuleName}"
    resolve_target_parent_pom
    modDir="$(build_module_dir_common "$mod")"
    ensure_module_dir_absent_common "$modDir"

    load_parent_coordinates "${targetParentPom}"
    create_maven_module "$mod" "$modDir" "${modulePackaging}" "${dependencies}"
    append_module_to_parent_pom "${targetParentPom}" "$mod"
    echo "Maven 子模块追加完成: ${mod} (父模块路径: ${modulePath:-<项目根>}, packaging=${modulePackaging})"
else
    # 子模块 parent.version 统一引用 ${revision}
    parentVersion='${revision}'
    escapedGroupId="$(xml_escape "$groupId")"
    escapedArtifactId="$(xml_escape "$artifactId")"
    escapedProjectVersion="$(xml_escape "$projectVersion")"
    escapedProjectName="$(xml_escape "$projectName")"
    escapedDescription="$(xml_escape "$description")"
    escapedBootVersion="$(xml_escape "$bootVersion")"
    # 创建父项目目录
    mkdir -p "${projectName}"
    write_project_gitignore "${projectName}"

    # 构建 <modules> 块
    modulesXml=""
    if [ -n "$subModules" ]; then
        modulesXml="    <modules>"$'\n'
        while IFS= read -r mod; do
            [ -z "$mod" ] && continue
            modulesXml+="        <module>${mod}</module>"$'\n'
        done < <(iterate_csv_items_common "$subModules")
        modulesXml+="    </modules>"$'\n'
    fi

    # 生成父 pom.xml（BOM 模式，不继承 spring-boot-starter-parent）
    # 注意: heredoc 未加引号，Maven 属性需写成 \${...}，避免被 bash 展开
    cat > "${projectName}/pom.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>${escapedGroupId}</groupId>
    <artifactId>${escapedArtifactId}</artifactId>
    <version>\${revision}</version>
    <packaging>pom</packaging>
    <name>${escapedProjectName}</name>
    <description>${escapedDescription}</description>

    <properties>
        <java.version>${javaVersion}</java.version>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <project.reporting.outputEncoding>UTF-8</project.reporting.outputEncoding>
        <revision>${escapedProjectVersion}</revision>
        <spring.boot.version>${escapedBootVersion}</spring.boot.version>
        <!-- <spring-cloud.version>2025.0.0</spring-cloud.version> -->
        <!-- <spring-cloud-alibaba.version>2025.0.0.0</spring-cloud-alibaba.version> -->
    </properties>

${modulesXml}
    <dependencyManagement>
        <dependencies>
            <!-- Spring Boot 依赖 BOM（不是 starter-parent） -->
            <dependency>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-dependencies</artifactId>
                <version>\${spring.boot.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>

            <!-- Spring Cloud 依赖 BOM（按需取消注释）
            <dependency>
                <groupId>org.springframework.cloud</groupId>
                <artifactId>spring-cloud-dependencies</artifactId>
                <version>\${spring-cloud.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
            -->

            <!-- Spring Cloud Alibaba 依赖 BOM（按需取消注释）
            <dependency>
                <groupId>com.alibaba.cloud</groupId>
                <artifactId>spring-cloud-alibaba-dependencies</artifactId>
                <version>\${spring-cloud-alibaba.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
            -->
        </dependencies>
    </dependencyManagement>

    <build>
        <pluginManagement>
            <plugins>
                <plugin>
                    <groupId>org.apache.maven.plugins</groupId>
                    <artifactId>maven-compiler-plugin</artifactId>
                    <version>3.13.0</version>
                    <configuration>
                        <release>\${java.version}</release>
                        <encoding>\${project.build.sourceEncoding}</encoding>
                    </configuration>
                </plugin>
                <plugin>
                    <groupId>org.springframework.boot</groupId>
                    <artifactId>spring-boot-maven-plugin</artifactId>
                    <version>\${spring.boot.version}</version>
                </plugin>
            </plugins>
        </pluginManagement>

        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
            </plugin>
        </plugins>
    </build>

</project>
EOF

    # 生成子模块
    if [ -n "$subModules" ]; then
        while IFS= read -r mod; do
            [ -z "$mod" ] && continue
            create_maven_module "$mod" "${projectName}/${mod}" "jar" "${dependencies}"
        done < <(iterate_csv_items_common "$subModules")
    fi
    echo "Maven 多模块项目创建完成"
fi
