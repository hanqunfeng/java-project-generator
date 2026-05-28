#!/usr/bin/env bash
# ========= 单模块项目（jar / war）=========
# 本脚本由入口脚本 springboot 通过 source 加载，直接使用其已解析的变量：
#   projectName, bootVersion, projectType, packaging, configFormat,
#   javaVersion, groupId, artifactId, projectVersion, description, packageName,
#   dependencies
#
# API 参考: https://docs.spring.io/initializr/docs/current/reference/html/#api-guide
# 或通过 curl https://start.spring.io/metadata/client 查看所有可选参数

source "${SCRIPT_DIR}/lib/project-common.sh"

zipFile="${projectName}.zip"
projectDir="${projectName}"
# 退出码沿用入口定义，支持脚本独立 source 时回退默认值。
exit_network="${EXIT_NETWORK:-2}"
exit_fs="${EXIT_FS:-3}"
# starter.zip 的 Boot 参数键由入口探测后注入。
boot_param_key="${bootParamKeyStarter:-bootVersion}"

# -----------------------------------------------------------------------------
# 函数: print_single_plan
# 作用: dry-run 输出单模块创建计划，确保“所见即将执行”。
# -----------------------------------------------------------------------------
print_single_plan() {
    plan_echo "NETWORK" "准备下载 Spring Initializr 压缩包到 '${zipFile}'"
    plan_echo "NETWORK" "执行 curl 请求: https://start.spring.io/starter.zip (type=${projectType}-project, ${boot_param_key}=${bootVersion}, packaging=${packaging}, javaVersion=${javaVersion})"
    plan_echo "NETWORK" "附带元数据参数: groupId=${groupId}, artifactId=${artifactId}, version=${projectVersion}, name=${projectName}, packageName=${packageName}, config=${configFormat}, dependencies=${dependencies}"
    plan_echo "ROLLBACK" "若下载失败: 打印错误并执行回滚 (删除 '${zipFile}' 与可能存在的 '${projectDir}')"
    plan_echo "WRITE" "下载成功后解压 '${zipFile}' 到目录 '${projectDir}'"
    plan_echo "ROLLBACK" "若解压失败: 打印错误并执行回滚 (删除 '${zipFile}' 与 '${projectDir}')"
    plan_echo "CLEANUP" "解压成功后删除压缩包 '${zipFile}'"
    plan_echo "CLEANUP" "清理模板冗余文件: '${projectDir}/mvnw' '${projectDir}/mvnw.cmd' '${projectDir}/.mvn' '${projectDir}/gradlew' '${projectDir}/gradlew.bat' '${projectDir}/gradle' '${projectDir}/HELP.md'"
    plan_echo "WRITE" "生成版本控制忽略文件: '${projectDir}/.gitignore'"
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

if ! curl --fail --show-error --location --retry 3 --retry-delay 1 --no-progress-meter https://start.spring.io/starter.zip \
    -d type="${projectType}-project" \
    -d "${boot_param_key}=${bootVersion}" \
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
    echo "下载失败: 请检查网络连接或 Spring Initializr 服务是否可用"
    rollback_single_project
    exit "$exit_network"
fi

if ! unzip -q "${zipFile}" -d "${projectDir}"; then
    echo "解压失败: 下载包可能损坏或 unzip 命令不可用"
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
