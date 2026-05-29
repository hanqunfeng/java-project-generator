#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WORK_DIR="$(mktemp -d)"
  cd "$WORK_DIR"
}

teardown() {
  rm -rf "$WORK_DIR"
}

@test "integration: create maven multi module and remove module" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --packaging=pom --type=maven --modules=api,service --language=java
  [ "$status" -eq 0 ]
  [ -f "abcde/pom.xml" ]
  [ -d "abcde/api" ]

  run bash "$PROJECT_ROOT/springboot" module remove --name=abcde --type=maven --module=api
  [ "$status" -eq 0 ]
  [ ! -d "abcde/api" ]
}

@test "integration: create gradle kotlin dsl project and module list" {
  run bash "$PROJECT_ROOT/springboot" create --name=abcde --packaging=pom --type=gradle --modules=api --gradle-dsl=kotlin --language=kotlin
  [ "$status" -eq 0 ]
  [ -f "abcde/settings.gradle.kts" ]
  [ -f "abcde/api/build.gradle.kts" ]

  run bash "$PROJECT_ROOT/springboot" module list --name=abcde --type=gradle
  [ "$status" -eq 0 ]
  [[ "$output" == *"api"* ]]
}
