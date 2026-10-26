#!/usr/bin/env bash
# ========= 单模块项目（jar / war）=========
# 本脚本由入口脚本 springboot 通过 source 加载，直接使用其已解析的变量：
#   projectName, bootVersion, projectType, packaging, configFormat,
#   javaVersion, groupId, artifactId, projectVersion, description, packageName,
#   dependencies
#
# API 参考: https://docs.spring.io/initializr/docs/current/reference/html/#api-guide
# 或通过 curl ${INITIALIZR_BASE_URL:-https://start.spring.io}/metadata/client 查看所有可选参数

source "${SCRIPT_DIR}/lib/project-common.sh"
if ! declare -F t >/dev/null 2>&1; then
    # shellcheck source=lib/i18n.sh
    source "${SCRIPT_DIR}/lib/i18n.sh"
fi

zipFile="${projectName}.zip"
projectDir="${projectName}"
# 退出码沿用入口定义，支持脚本独立 source 时回退默认值。
exit_network="${EXIT_NETWORK:-2}"
exit_fs="${EXIT_FS:-3}"
# starter.zip 的 Boot 参数键由入口探测后注入。
boot_param_key="${bootParamKeyStarter:-bootVersion}"
project_language="${projectLanguage:-java}"

# -----------------------------------------------------------------------------
# 函数: print_single_plan
# 作用: dry-run 输出单模块创建计划，确保“所见即将执行”。
# -----------------------------------------------------------------------------
print_single_plan() {
    plan_echo "NETWORK" "$(t "Prepare to download the Spring Initializr archive to '${zipFile}'" "准备下载 Spring Initializr 压缩包到 '${zipFile}'")"
    plan_echo "NETWORK" "$(t "Run curl: $(initializr_url "starter.zip") (type=${projectType}-project, ${boot_param_key}=${bootVersion}, packaging=${packaging}, javaVersion=${javaVersion}, language=${project_language})" "执行 curl 请求: $(initializr_url "starter.zip") (type=${projectType}-project, ${boot_param_key}=${bootVersion}, packaging=${packaging}, javaVersion=${javaVersion}, language=${project_language})")"
    plan_echo "NETWORK" "$(t "Metadata: groupId=${groupId}, artifactId=${artifactId}, version=${projectVersion}, name=${projectName}, packageName=${packageName}, config=${configFormat}, dependencies=${dependencies}" "附带元数据参数: groupId=${groupId}, artifactId=${artifactId}, version=${projectVersion}, name=${projectName}, packageName=${packageName}, config=${configFormat}, dependencies=${dependencies}")"
    plan_echo "ROLLBACK" "$(t "If the download fails: print the error and roll back (delete '${zipFile}' and '${projectDir}' if it exists)" "若下载失败: 打印错误并执行回滚 (删除 '${zipFile}' 与可能存在的 '${projectDir}')")"
    plan_echo "WRITE" "$(t "After a successful download, unzip '${zipFile}' into '${projectDir}'" "下载成功后解压 '${zipFile}' 到目录 '${projectDir}'")"
    plan_echo "ROLLBACK" "$(t "If unzip fails: print the error and roll back (delete '${zipFile}' and '${projectDir}')" "若解压失败: 打印错误并执行回滚 (删除 '${zipFile}' 与 '${projectDir}')")"
    plan_echo "CLEANUP" "$(t "After a successful unzip, delete the archive '${zipFile}'" "解压成功后删除压缩包 '${zipFile}'")"
    plan_echo "CLEANUP" "$(t "Remove template extras: '${projectDir}/mvnw' '${projectDir}/mvnw.cmd' '${projectDir}/.mvn' '${projectDir}/gradlew' '${projectDir}/gradlew.bat' '${projectDir}/gradle' '${projectDir}/HELP.md'" "清理模板冗余文件: '${projectDir}/mvnw' '${projectDir}/mvnw.cmd' '${projectDir}/.mvn' '${projectDir}/gradlew' '${projectDir}/gradlew.bat' '${projectDir}/gradle' '${projectDir}/HELP.md'")"
    plan_echo "WRITE" "$(t "Write the VCS ignore file: '${projectDir}/.gitignore'" "生成版本控制忽略文件: '${projectDir}/.gitignore'")"
}

# -----------------------------------------------------------------------------
# 函数: rollback_single_project
# 作用: 下载/解压失败时清理半成品，保证幂等重试体验。
# -----------------------------------------------------------------------------
rollback_single_project() {
    # 失败时清理半成品目录和下载包，避免留下脏状态
    rm -f "${zipFile}"
    if [ -d "${projectDir}" ]; then
        rm -rf "${projectDir}"
    fi
}

if [[ "${dryRun:-false}" == "true" ]]; then
    print_single_plan
    return 0
fi

if ! curl --fail --show-error --location --retry 3 --retry-delay 1 --no-progress-meter "$(initializr_url "starter.zip")" \
    -d type="${projectType}-project" \
    -d "${boot_param_key}=${bootVersion}" \
    -d language="${project_language}" \
    -d packaging="${packaging}" \
    -d javaVersion="${javaVersion}" \
    -d groupId="${groupId}" \
    -d artifactId="${artifactId}" \
    -d version="${projectVersion}" \
    -d name="${projectName}" \
    -d description="$description" \
    -d packageName="${packageName}" \
    -d configurationFileFormat="${configFormat}" \
    -d dependencies="${dependencies}" \
    -o "${zipFile}"; then
    say "Download failed. Check the network connection or whether the Spring Initializr service is available" "下载失败: 请检查网络连接或 Spring Initializr 服务是否可用"
    rollback_single_project
    exit "$exit_network"
fi

if ! unzip -q "${zipFile}" -d "${projectDir}"; then
    say "Unzip failed. The archive may be corrupt, or the unzip command is unavailable" "解压失败: 下载包可能损坏或 unzip 命令不可用"
    rollback_single_project
    exit "$exit_fs"
fi

rm -f "${zipFile}"

# 删除不需要的文件
if [ -f "${projectDir}/mvnw" ]; then
    rm -f "${projectDir}/mvnw"
    rm -f "${projectDir}/mvnw.cmd"
    rm -rf "${projectDir}/.mvn"
fi
if [ -f "${projectDir}/gradlew" ]; then
    rm -f "${projectDir}/gradlew"
    rm -f "${projectDir}/gradlew.bat"
    rm -rf "${projectDir}/gradle"
fi
rm -f "${projectDir}/HELP.md"
write_project_gitignore "${projectDir}"
