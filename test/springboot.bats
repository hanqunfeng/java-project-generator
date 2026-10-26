#!/usr/bin/env bats

# 每个用例前准备独立临时工作目录，避免测试间相互污染。
setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WORK_DIR="$(mktemp -d)"
  cd "$WORK_DIR"
  export DEPS_CACHE_DIR="$WORK_DIR/deps-cache"
  mkdir -p "$DEPS_CACHE_DIR"
  cat > "$DEPS_CACHE_DIR/boot-versions.tsv" <<'EOF'
DEFAULT	4.0.7.RELEASE
4.1.0.RELEASE	4.1.0
4.0.7.RELEASE	4.0.7
EOF
}

# 每个用例后清理临时目录。
teardown() {
  rm -rf "$WORK_DIR"
}

@test "显示帮助信息成功" {
  run bash "$PROJECT_ROOT/springboot" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"springboot <command>"* ]]
  [[ "$output" != *"用法:"* ]]
}

@test "--zh 输出中文帮助和错误" {
  run bash "$PROJECT_ROOT/springboot" --zh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"用法:"* ]]
  [[ "$output" == *"--zh"* ]]

  run bash "$PROJECT_ROOT/springboot" create --help --zh
  [ "$status" -eq 0 ]
  [[ "$output" == *"项目名"* ]]

  run bash "$PROJECT_ROOT/springboot" create --zh --type=maven
  [ "$status" -eq 1 ]
  [[ "$output" == *"缺少必填参数"* ]]
}

@test "create 缺少项目名返回参数错误" {
  run bash "$PROJECT_ROOT/springboot" create --type=maven
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required argument"* ]]
}

@test "groupId 含短横线时默认 packageName 自动修正" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --group=com.my-company --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Root package:"*"com.my_company"* ]]
}

@test "dry-run 不触发联网依赖校验" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --deps=not-real-dep --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry-run mode"* ]]
}

@test "非法 bootVersion 被拦截" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --boot=3.5.14/evil --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid Boot version"* ]]
}

@test "未指定 boot 时使用 Initializr 默认版本" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Boot version:"*"4.0.7"* ]]
}

@test "指定已下线 boot 版本时提示官方不再支持" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --boot=3.5.14 --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"no longer supported by the current Initializr"* ]]
  [[ "$output" == *"springboot boot list"* ]]
}

@test "指定简写 boot 版本可匹配目录并规范化" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --boot=4.0.7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Boot version:"*"4.0.7"* ]]
}


@test "artifact-version 参数生效" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --artifact-version=1.2.0 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Project version:"*"1.2.0"* ]]
}

@test "pom 模式下允许 --deps 并应用到子模块计划" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --packaging=pom --type=maven --modules=api --deps=webflux --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Module deps:"*"webflux"* ]]
  [[ "$output" == *"Write module dependencies: 'abcde/api/pom.xml' <- --deps=webflux"* ]]
}

@test "deps preview 缺少 deps 返回参数错误" {
  run bash "$PROJECT_ROOT/springboot" deps preview --deps=
  [ "$status" -eq 1 ]
  [[ "$output" == *"deps preview requires --deps"* ]]
}

@test "create 模式下误传 module-path 被拦截" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --module-path=platform --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown create argument"* ]]
}

@test "modules 会去重并保留首出现顺序" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --packaging=pom --type=maven --modules="api, service ,api,dao" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Modules:"*"api,service,dao"* ]]
}

@test "Maven 多模块 dry-run 输出父 POM 与模块计划" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --packaging=pom --type=maven --modules=api,service --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Generate parent POM file: 'abcde/pom.xml'"* ]]
  [[ "$output" == *"Generate module POM: 'abcde/api/pom.xml'"* ]]
  [[ "$output" == *"Maven multi-module project created"* ]]
}

@test "Gradle 多模块 dry-run 输出 settings 与 include 计划" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --packaging=pom --type=gradle --modules=api,service --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Generate settings.gradle: 'abcde/settings.gradle'"* ]]
  [[ "$output" == *"include ':api'"* ]]
  [[ "$output" == *"Gradle multi-module project created"* ]]
}

@test "Gradle 多模块 dry-run 展示 --deps 注入计划" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --packaging=pom --type=gradle --modules=api --deps=web,data-jpa --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Module deps:"*"web,data-jpa"* ]]
  [[ "$output" == *"Write module dependencies: 'abcde/api/build.gradle' <- --deps=web,data-jpa"* ]]
}

@test "add-module 模式要求项目目录存在" {
  run bash "$PROJECT_ROOT/springboot" module add --name=abcde --type=maven --module=api --dry-run
  [ "$status" -eq 3 ]
  [[ "$output" == *"Project directory does not exist: abcde"* ]]
}

@test "add-module 模式必须提供 module 参数" {
  mkdir -p abcde
  run bash "$PROJECT_ROOT/springboot" module add --name=abcde --type=maven --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"module add requires --module=<module name>"* ]]
}

@test "add-module 显式传非 pom 的 packaging 会被拦截" {
  mkdir -p abcde
  run bash "$PROJECT_ROOT/springboot" module add --name=abcde --type=maven --packaging=jar --module=api --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"module add only supports multi-module projects: use --packaging=pom"* ]]
}

@test "Gradle add-module 检测到重复 include 时失败" {
  mkdir -p abcde
  cat > abcde/settings.gradle <<'EOF'
rootProject.name = 'abcde'
include ':api'
EOF
  run bash "$PROJECT_ROOT/springboot" module add --name=abcde --packaging=pom --type=gradle --module=api
  [ "$status" -eq 1 ]
  [[ "$output" == *"Module already exists in settings.gradle: :api"* ]]
}

@test "Maven add-module 检测到模块目录已存在时失败" {
  mkdir -p abcde/api
  cat > abcde/pom.xml <<'EOF'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>abcde</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <packaging>pom</packaging>
</project>
EOF
  run bash "$PROJECT_ROOT/springboot" module add --name=abcde --packaging=pom --type=maven --module=api
  [ "$status" -eq 1 ]
  [[ "$output" == *"Module directory already exists: abcde/api"* ]]
}

@test "add-module 创建聚合模块时忽略 --deps 并给出提示" {
  mkdir -p abcde
  cat > abcde/pom.xml <<'EOF'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>abcde</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <packaging>pom</packaging>
</project>
EOF
  run bash "$PROJECT_ROOT/springboot" module add --name=abcde --packaging=pom --type=maven --module=platform --module-packaging=pom --deps=webflux
  [ "$status" -eq 0 ]
  [[ "$output" == *"when module-packaging=pom"* ]]
  [[ "$output" == *"Created module: platform (packaging=pom, deps=ignored)"* ]]
}

@test "创建 Maven 多模块项目会生成统一 .gitignore" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --packaging=pom --type=maven --modules=api
  [ "$status" -eq 0 ]
  [ -f "abcde/.gitignore" ]
}

@test "创建 Gradle 多模块项目会生成统一 .gitignore" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --packaging=pom --type=gradle --modules=api
  [ "$status" -eq 0 ]
  [ -f "abcde/.gitignore" ]
}

@test "deps list 支持 output=web 参数" {
  run bash "$PROJECT_ROOT/springboot" deps list --output=markdown --boot=3.5.14
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid --output"* ]]
}

@test "deps preview 在网络失败时返回网络错误码" {
  mkdir -p "$WORK_DIR/fakebin"
  cat > "$WORK_DIR/fakebin/curl" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
  chmod +x "$WORK_DIR/fakebin/curl"

  run env PATH="$WORK_DIR/fakebin:/usr/bin:/bin" bash "$PROJECT_ROOT/springboot" deps preview --deps=web --type=maven
  [ "$status" -eq 2 ]
  [[ "$output" == *"Failed to fetch dependency declarations"* ]]
}

@test "Maven module add 在外部解析器缺失时回退 awk 解析父坐标" {
  mkdir -p "$WORK_DIR/fakebin"
  cat > "$WORK_DIR/fakebin/mvn" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  cat > "$WORK_DIR/fakebin/xmllint" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  cat > "$WORK_DIR/fakebin/xmlstarlet" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$WORK_DIR/fakebin/mvn" "$WORK_DIR/fakebin/xmllint" "$WORK_DIR/fakebin/xmlstarlet"

  mkdir -p abcde
  cat > abcde/pom.xml <<'EOF'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>abcde</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <packaging>pom</packaging>
</project>
EOF

  run env PATH="$WORK_DIR/fakebin:/usr/bin:/bin" bash "$PROJECT_ROOT/springboot" module add --name=abcde --type=maven --module=platform --module-packaging=pom
  [ "$status" -eq 0 ]
  [[ "$output" == *"[source: awk(fallback)]"* ]]
  [[ "$output" == *"Maven module added: platform"* ]]
  [ -f "abcde/platform/pom.xml" ]
}

@test "Maven module add 支持多层 module-path 并挂载到目标父模块" {
  mkdir -p abcde/platform/common-parent
  cat > abcde/pom.xml <<'EOF'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>abcde</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <packaging>pom</packaging>
</project>
EOF
  cat > abcde/platform/pom.xml <<'EOF'
<project>
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.example</groupId>
    <artifactId>abcde</artifactId>
    <version>0.0.1-SNAPSHOT</version>
  </parent>
  <artifactId>platform</artifactId>
  <packaging>pom</packaging>
</project>
EOF
  cat > abcde/platform/common-parent/pom.xml <<'EOF'
<project>
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.example</groupId>
    <artifactId>platform</artifactId>
    <version>0.0.1-SNAPSHOT</version>
  </parent>
  <artifactId>common-parent</artifactId>
  <packaging>pom</packaging>
</project>
EOF

  run bash "$PROJECT_ROOT/springboot" module add --name=abcde --type=maven --module-path=platform/common-parent --module=order-service --module-packaging=pom
  [ "$status" -eq 0 ]
  [[ "$output" == *"Maven module added: order-service (parent path: platform/common-parent, packaging=pom)"* ]]
  [ -d "abcde/platform/common-parent/order-service" ]
  [ -f "abcde/platform/common-parent/order-service/pom.xml" ]
  run rg "<module>order-service</module>" "abcde/platform/common-parent/pom.xml"
  [ "$status" -eq 0 ]
}

@test "子命令帮助可用" {
  run bash "$PROJECT_ROOT/springboot" create --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"springboot create"* ]]

  run bash "$PROJECT_ROOT/springboot" module add --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"springboot module add"* ]]

  run bash "$PROJECT_ROOT/springboot" deps list --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--output=<value>"* ]]

  run bash "$PROJECT_ROOT/springboot" boot list --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"springboot boot list"* ]]
}

@test "boot 未知子命令返回参数错误" {
  run bash "$PROJECT_ROOT/springboot" boot unknown
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown subcommand: boot unknown"* ]]
}

@test "支持 language 与 gradle-dsl 参数（dry-run）" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --type=gradle --packaging=pom --modules=api --language=kotlin --gradle-dsl=kotlin --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Language:"*"kotlin"* ]]
  [[ "$output" == *"Gradle DSL:"*"kotlin"* ]]
}

@test "Maven 项目配置输出不包含 Gradle DSL" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --type=maven --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"Gradle DSL:"* ]]
}

@test "module list 支持 maven 项目" {
  mkdir -p abcde
  cat > abcde/pom.xml <<'EOF'
<project>
  <modules>
    <module>api</module>
    <module>service</module>
  </modules>
</project>
EOF
  run bash "$PROJECT_ROOT/springboot" module list --name=abcde --type=maven
  [ "$status" -eq 0 ]
  [[ "$output" == *"api"* ]]
  [[ "$output" == *"service"* ]]
}

@test "deps search 关键词参数校验" {
  run bash "$PROJECT_ROOT/springboot" deps search --query=
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing --query argument"* ]]
}

@test "创建 Maven 多模块后子模块 pom.xml 包含 dependencies" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --packaging=pom --type=maven --modules=api
  [ "$status" -eq 0 ]
  [ -f "abcde/api/pom.xml" ]
  run rg "<dependencies>" "abcde/api/pom.xml"
  [ "$status" -eq 0 ]
}

@test "创建 Maven 多模块父 POM 使用 BOM 模式与 revision" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --packaging=pom --type=maven --modules=api --artifact-version=1.2.0 --boot=4.0.7
  [ "$status" -eq 0 ]
  [ -f "abcde/pom.xml" ]
  ! grep -q "spring-boot-starter-parent" "abcde/pom.xml"
  grep -q "<revision>1.2.0</revision>" "abcde/pom.xml"
  grep -q '<version>${revision}</version>' "abcde/pom.xml"
  grep -q "spring-boot-dependencies" "abcde/pom.xml"
  grep -q "maven-compiler-plugin" "abcde/pom.xml"
  grep -q "spring-cloud-dependencies" "abcde/pom.xml"
  grep -q "spring-cloud-alibaba-dependencies" "abcde/pom.xml"
  # Cloud BOM 位于注释块内（取消注释前不会生效）
  grep -q "Spring Cloud dependency BOM (uncomment if needed)" "abcde/pom.xml"
  grep -q "Spring Cloud Alibaba dependency BOM (uncomment if needed)" "abcde/pom.xml"
  grep -q '<version>${revision}</version>' "abcde/api/pom.xml"
  grep -q "spring-boot-maven-plugin" "abcde/api/pom.xml"
}

@test "创建 Gradle Kotlin DSL 多模块后生成 kts 文件" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --packaging=pom --type=gradle --modules=api --gradle-dsl=kotlin --language=kotlin
  [ "$status" -eq 0 ]
  [ -f "abcde/settings.gradle.kts" ]
  [ -f "abcde/api/build.gradle.kts" ]
  run rg "id\\(kotlin\\)" "abcde/api/build.gradle.kts"
  [ "$status" -eq 0 ]
}
