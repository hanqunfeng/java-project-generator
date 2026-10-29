# java-project-generator

[中文](README.zh-CN.md)


A script for quickly generating Spring Boot projects. It supports:

- Single-module projects (`jar` / `war`, fetched from Spring Initializr)
- Multi-module Maven projects (`pom`, parent/child layout generated locally)
- Multi-module Gradle projects (`pom` mode, parent/child layout generated locally)
- Adding modules to an existing Maven/Gradle multi-module project (including nested paths)

## Why this tool (compared with IDEA)

Compared with the IntelliJ IDEA “New Project → Spring Boot” wizard, this tool fits work that needs to be **reproducible, scriptable, multi-module, and not tied to one IDE**. A common setup is: generate the skeleton here, then open it in IDEA / VS Code / Cursor.

### Reasons to use this tool

1. **Scriptable and reproducible**: one command can live in shell history, a Makefile, or CI, so teammates and pipelines get the same layout. An IDEA click-through is hard to version.
2. **Works in a terminal with no GUI**: SSH, containers, and minimal environments do not need an IDE.
3. **Multi-module is closer to ready-made**: `packaging=pom` plus `--modules`, and `module add|list|remove` on an existing project (including nested paths), are aimed at building parent/child trees in bulk.
4. **Look up dependencies before writing them**: `boot list` / `deps list|search|preview` can check versions and coordinates before creation.
5. **Same source as the official Initializr, editor-agnostic**: not tied to IntelliJ.
6. **`--dry-run` previews the plan**: you can see what will be generated without writing files.

### Comparison

| Aspect | This tool | IDEA new-project wizard |
| --- | --- | --- |
| Interaction | CLI, suited to scripts / CI | GUI, easier for beginners |
| Reproducibility | The command itself reproduces the result | Depends on clicks, hard to automate |
| Single-module jar/war | Calls the official Initializr, close to start.spring.io | Also based on Initializr; picking dependencies is more visual |
| Multi-module / adding modules | Local templates, batch create and maintain modules | Mostly manual or via plugins |
| Run and debug setup | Does not generate IDE run configurations | Often includes run and module setup after creation |
| Boot versions | Only the current official list; older versions must be edited by hand | Also limited by Initializr, but the UI makes the choices easier to see |
| Finding dependencies | Use `deps list` / the docs | Search-and-check is friendlier |
| Environment | bash, curl, python3, network, and so on | IDEA is enough (it still needs access to Initializr) |
| Editor lock-in | None | Tied to the IntelliJ ecosystem |

### Tradeoffs versus IDEA

1. **Learning cost**: you need the subcommands and flags. A wizard is more “click and go”.
2. **No IDE integration**: it does not configure Run/Debug or set a Spring facet.
3. **A clear boundary**: versions follow the official site. Complex company templates or paid scaffolds are out of scope.
4. **You watch dependency coordinates across major versions**: for example Boot 3 `spring-boot-starter-web` versus Boot 4 `spring-boot-starter-webmvc`. After changing the version you may need to edit coordinates by hand (see “Spring Boot versions” below).

### How to choose

- You want **repeatable, multi-module, terminal/CI, and not tied to IDEA** → use this tool.
- You want **to pick dependencies visually and run in IDEA immediately** → use IDEA (or generate here, then open the project).

## Layout

```text
java-project-generator/
├── springboot         # Entry script: parse args, validate, dispatch
├── deps-cache/        # Dependency cache and web render output
│   ├── boot-<ver>.md
│   └── boot-web.html
├── assets/            # Static assets (for example web CSS)
│   └── web_style.css
├── completions/       # Shell completion scripts
│   ├── springboot.bash
│   └── _springboot
├── scripts/
│   └── check.sh       # Local check entry (shellcheck + bats)
└── lib/
    ├── arg-common.sh  # Shared argument helpers (CSV normalize/iterate)
    ├── deps.sh        # Dependency / Initializr interaction (cache, declaration extraction, deps subcommands)
    ├── single.sh      # Single-module generation (jar/war)
    ├── multi-maven.sh # Maven multi-module generation
    ├── multi-gradle.sh # Gradle multi-module generation
    ├── nested-common.sh # Shared nested-module logic
    ├── module-template-common.sh # Shared module skeleton templates
    └── project-common.sh # Project-level helpers (for example .gitignore)
```

## How it works

- `springboot` parses arguments, validates them, and prints the configuration
- `INITIALIZR_BASE_URL` can override the default Initializr address (it must speak the official API; only the official service is usable today — see environment variables below)
- Dispatch follows `--packaging`:
  - `jar` / `war` -> `lib/single.sh`
  - `pom` + `--type=maven` -> `lib/multi-maven.sh`
  - `pom` + `--type=gradle` -> `lib/multi-gradle.sh`
- Child scripts are `source`d by the entry script and reuse the parsed variables, which keeps later extensions local

## Requirements

- `bash`
- `curl`
- `unzip` (single-module mode needs it to unpack starter.zip)
- `python3` (dependency metadata parsing and dependency ID checks)
- `pandoc` (`springboot deps list --output=web` renders HTML)
- `glow` (`springboot deps list --output=terminal` renders in the terminal; if it is missing, read the cache file directly)
- `mvn` / `xmllint` / `xmlstarlet` (Maven module add coordinate parsing; any one in the fallback chain is enough)
- Network access to Spring Initializr (default `https://start.spring.io`; `INITIALIZR_BASE_URL` is reserved for a compatible official-API endpoint — see below)
- The script detects the Boot version parameter name (`bootVersion` / `boot-version`) and handles `metadata/client` and `starter.zip` separately

## Compatibility (suggested)

| Item | Suggested version / platform | Notes |
| --- | --- | --- |
| OS | macOS / Linux | Covers `open` / `xdg-open` |
| Bash | `4.0+` | Required by the entry script and child scripts |
| Zsh | `5.0+` | Only for loading the `_springboot` completion |
| Java | `17` / `21` / `25` | Matches argument validation |
| Build tool | Maven / Gradle | Matches `--type` |

## Install and global command

### Option 1: Homebrew (recommended)

```bash
brew install hanqunfeng/tap/java-project-generator
```

Or in two steps:

```bash
brew tap hanqunfeng/tap
brew install java-project-generator
```

Install **python3** yourself afterwards (the formula does not install it; project generation and dependency features need it):

```bash
brew install python@3.13
```

Check:

```bash
springboot --help
springboot --version
```

Upgrade / uninstall:

```bash
brew update && brew upgrade java-project-generator
brew uninstall java-project-generator
```

Homebrew also installs the Bash / Zsh completions. See [`formula/README.md`](formula/README.md) for more.

### Option 2: add the source tree to PATH

`$REPO_ROOT` below is this repository root (the cloned `java-project-generator` path). Replace it before copying commands, for example:

```bash
export REPO_ROOT="$(cd /path/to/java-project-generator && pwd)"
```

From the current directory:

```bash
chmod +x springboot scripts/check.sh lib/single.sh lib/multi-maven.sh lib/multi-gradle.sh lib/nested-common.sh lib/module-template-common.sh lib/project-common.sh lib/arg-common.sh lib/deps.sh
```

Add the directory to PATH (`zsh` example):

```bash
echo 'export PATH="'"$REPO_ROOT"':$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Check:

```bash
springboot create --name=mydemo
```

## Shell completion

A Homebrew install already sets up Bash / Zsh completion, so you usually do not configure it again. When running from source, load it as below.

### Bash

```bash
source "$REPO_ROOT/completions/springboot.bash"
```

To keep it, append that line to `~/.bashrc`.

`--deps=` completion reads the local cache. Generate it once first:

```bash
springboot deps list --boot=3.5.14
```

### Zsh

```bash
fpath=("$REPO_ROOT/completions" $fpath)
autoload -Uz compinit && compinit
```

To keep it, append those lines to `~/.zshrc`.

`--deps=` completion reads the local cache. Generate it once first:

```bash
springboot deps list --boot=3.5.14
```

## Usage

Basic form:

```bash
springboot <command> [options]
```

### Commands

- Entry commands:
  - `springboot create`: create a project (single-module or multi-module)
  - `springboot module add|list|remove`: maintain a multi-module project
  - `springboot deps list|preview|search`: dependency list, declaration preview, and keyword search
  - `springboot boot list`: list Spring Boot versions the current Initializr can create
- Top-level commands and subcommands accept `--help` / `-h`
- `--deps` accepts only dependency IDs from the official Spring Boot Initializr (for example `web`, `data-jpa`, `mysql`)
- Creatable Boot versions change as the official Initializr changes. **Check first** with `springboot boot list`, then `springboot deps list --boot=<version>` for dependency IDs (see “Spring Boot versions” below)
- `create` / `module add`: when `--boot` is omitted, the current Initializr default is used. A version that is not on the official list is reported as no longer supported
- Command output is English by default. Add `--zh` for Chinese (it can appear anywhere, for example `springboot --zh --help`)
- Colored success/warning/error output is on by default. Set `NO_COLOR=1` to turn it off

### Spring Boot versions

The Spring Boot versions this tool can create **follow** the list currently published by the official Initializr (`https://start.spring.io`). That list grows and shrinks with the site. **There is no built-in fixed version matrix.**

Before a release or before use, check:

```bash
springboot boot list
# optional: force a cache refresh
springboot boot list --refresh
```

At a given moment the official list might keep only Boot 4.x and drop 3.x. Then `--boot=3.5.x` is rejected.

#### When you need an older version

An old version that is not on the official list **cannot** be generated through Initializr anymore. A common approach:

1. Create the project with a version the official list still supports (include the `--deps` you need)
2. Edit the Boot version in `pom.xml` / `build.gradle` to the older target by hand
3. If dependencies were included at creation time, after a major-version change you **usually also need to check and edit dependency coordinates** (the Initializr dependency ID may still be `web`, while the `artifactId` written into the build file changes with the Boot major version)

#### Example: the Web starter name differs from Boot 3 to Boot 4

The Initializr dependency ID can be `web` on both sides, but the Maven coordinates differ:

**Spring Boot 3.x** (the historical form):

```xml
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-web</artifactId>
</dependency>
```

**Spring Boot 4.x** (what the official site generates now):

```xml
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-webmvc</artifactId>
</dependency>

<!-- Test dependencies change too, for example: -->
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-webmvc-test</artifactId>
  <scope>test</scope>
</dependency>
```

So if you generate with Boot 4 and then edit the project back to Boot 3, change `spring-boot-starter-webmvc` back to `spring-boot-starter-web` (and check test dependencies). The reverse applies when moving from Boot 3 to 4. Other starters can be renamed the same way. After a major bump, compare the target version’s dependency notes, or check coordinates with `springboot deps preview --boot=<version-still-supported> --deps=...`.

### Environment variables (optional)

- `NO_COLOR`: disable colored output. Any non-empty value works (common: `NO_COLOR=1`)
- `INITIALIZR_BASE_URL`: override the Spring Initializr base URL (default `https://start.spring.io`)
  - **Requirement**: a base URL compatible with the [Spring Initializr](https://github.com/spring-io/initializr) HTTP API (the script calls `{BASE}/metadata/client`, `{BASE}/starter.zip`, and similar paths)
  - **Today**: only the official `https://start.spring.io` is a verified target. The variable is reserved for later use (for example a self-hosted or intranet Initializr)
  - **Not supported**: unofficial sites such as Aliyun `https://start.aliyun.com`. Even if the page opens, path, access control, or metadata differences usually make them unusable as this tool’s Initializr backend
  - Example (the default is enough; you usually do not need to set this):
    ```bash
    export INITIALIZR_BASE_URL=https://start.spring.io
    ```
- `DEPS_CACHE_TTL_SECONDS`: dependency cache TTL in seconds (default `86400`)
- `GRADLE_DM_PLUGIN_VERSION`: override the `io.spring.dependency-management` plugin version in Gradle multi-module templates. Default `1.1.7`
  - Example: `GRADLE_DM_PLUGIN_VERSION=1.1.6 springboot create --name=myproject --type=gradle --packaging=pom --modules=api`
- `EXIT_PARAM` / `EXIT_NETWORK` / `EXIT_FS` / `EXIT_DEP`: fallback exit codes when a child script is run or debugged outside the entry script (a normal `springboot` invocation uses the built-in codes)

## Examples

### Shortest path for a new user (3 steps)

1) Confirm the script works, and see which Boot versions can be created now:

```bash
springboot --help
springboot boot list
```

2) Preview the plan with dry-run (no files are created):

```bash
springboot create --name=mydemo --boot=4.0.7 --dry-run
```

3) Create the project once the arguments look right:

```bash
springboot create --name=mydemo
```

Start with the defaults (`maven + jar`) the first time. After that flow is familiar, add `--type`, `--packaging`, `--modules`, and other options.

1) Create a single module quickly (Maven + jar + default dependencies):

```bash
springboot create --name=mydemo
```

2) Show help and version:

```bash
springboot --help
springboot --version
```

3) Print the execution plan only (no files are written):

```bash
springboot create --name=mydemo --dry-run
```

Notes:

- After validation, dry-run prints every step that would run (target paths, key arguments, and branches)
- It covers single-module, multi-module, and `module add`
- It only prints the plan. It does not run `mkdir`, `touch`, `curl`, `unzip`, or file writes

4) Create a single module with the main options customized (Gradle + war + Java 21):

```bash
springboot create --name=mydemo --type=gradle --packaging=war --java=21
```

5) Create a single module with a custom package and config format (group + pkg + yaml):

```bash
springboot create --name=mydemo --group=com.lexing --pkg=com.lexing.demo --config=yaml
```

6) Create a single module with a project version:

```bash
springboot create --name=mydemo --artifact-version=1.2.0
```

7) List Boot versions the current Initializr supports:

```bash
springboot boot list
```

8) List dependencies for a Boot version (official Initializr):

```bash
springboot deps list --boot=4.0.7 --output=terminal
```

8) Open the dependency list in a browser (render and open HTML):

```bash
springboot deps list --boot=3.5.14 --output=web
```

9) Print a dependency declaration snippet (Maven by default):

```bash
springboot deps preview --boot=3.5.14 --deps=web,data-jpa,mysql
```

10) Print a dependency declaration snippet (Gradle):

```bash
springboot deps preview --type=gradle --boot=3.5.14 --deps=web,data-jpa,mysql
```

10.1) Print a Kotlin DSL dependency declaration snippet:

```bash
springboot deps preview --type=gradle --gradle-dsl=kotlin --language=kotlin --deps=web,data-jpa
```

11) Create a single module with a custom dependency ID list:

```bash
springboot create --name=mydemo --deps=web,data-jpa,mysql,lombok
```

12) Create a Maven multi-module project (parent + modules + shared dependencies):

```bash
springboot create --name=myproject --type=maven --packaging=pom --modules=api,service,common --deps=web,data-jpa
```

13) Create a Gradle multi-module project (group / Java / shared dependencies):

```bash
springboot create --name=myproject --type=gradle --packaging=pom --group=com.lexing --java=21 --modules=api,service,common --deps=web,data-jpa
```

14) Add a module to an existing Maven multi-module project (with dependencies):

```bash
springboot module add --name=myproject --type=maven --module=order --deps=webflux
```

15) Add a `pom` module under the Maven project root (for another aggregator level):

```bash
springboot module add --name=myproject --type=maven --module=platform --module-packaging=pom
```

16) Add a `jar` module under the Maven `platform` module:

```bash
springboot module add --name=myproject --type=maven --module-path=platform --module=order-api --module-packaging=jar
```

17) Add a module under a nested Maven path:

```bash
springboot module add --name=myproject --type=maven --module-path=platform/common-parent --module=order-service --module-packaging=jar
```

18) Add a module to an existing Gradle multi-module project (with dependencies):

```bash
springboot module add --name=myproject --type=gradle --module=order --deps=webflux
```

19) Add an aggregator module under the Gradle project root (`module-packaging=pom` maps to an aggregator module):

```bash
springboot module add --name=myproject --type=gradle --module=platform --module-packaging=pom
```

20) Add a business module under a Gradle aggregator module:

```bash
springboot module add --name=myproject --type=gradle --module-path=platform --module=order-api --module-packaging=jar
```

21) List and remove modules:

```bash
springboot module list --name=myproject --type=maven
springboot module remove --name=myproject --type=gradle --module=order
```

22) Search dependencies:

```bash
springboot deps search --query=redis --boot=3.5.14
```

## What gets generated

### Single module (`jar` / `war`)

- Download and unzip the project from Spring Initializr
- Remove `mvnw`, `mvnw.cmd`, `.mvn`, `gradlew`, `gradlew.bat`, `gradle`, and `HELP.md`
- Write `.gitignore`

### Multi-module Maven (`--packaging=pom --type=maven`)

- Write a parent `pom.xml` (`packaging=pom`)
- The parent uses BOM mode (it does not inherit `spring-boot-starter-parent`) and manages versions through `spring-boot-dependencies`
- Uses the CI-friendly version property `${revision}` (`--artifact-version` is written to `<revision>`)
- The parent includes encoding, plus `pluginManagement` for `maven-compiler-plugin` and `spring-boot-maven-plugin`
- Spring Cloud / Spring Cloud Alibaba BOMs are included as comments; uncomment them when needed
- `--modules` can generate each module directory and its `pom.xml`
- `jar` module dependencies come from `--deps` (default `web,devtools`)
- Each module includes, by default:
  - `src/main/java/...`
  - `src/main/resources/application.properties` or `application.yaml`
  - `src/test/java/...`
- A `jar` module gets a minimal runnable `*Application.java` and `*ApplicationTests.java`, and declares `spring-boot-maven-plugin`
- The parent gets a `.gitignore`

### Multi-module Gradle (`--packaging=pom --type=gradle`)

- Write a root `settings.gradle` and root `build.gradle` (`settings.gradle.kts` and `build.gradle.kts` when `--gradle-dsl=kotlin`)
- `--modules` can generate each module directory and its `build.gradle` (`build.gradle.kts` for Kotlin DSL)
- `jar` module dependencies come from `--deps` (default `web,devtools`)
- Each module includes, by default:
  - `src/main/java/...`
  - `src/main/resources/application.properties` or `application.yaml`
  - `src/test/java/...`
- A `jar` module gets a minimal runnable `*Application.java` and `*ApplicationTests.java`
- The parent gets a `.gitignore`

## Arguments and validation

- For `springboot module add`:
  - `--module` is required
  - Only `--packaging=pom` is supported
  - The target project directory must already exist
  - `--module-packaging` is only `jar` / `pom`
  - `--module-path` must point at an existing parent module directory inside the project (relative path)
  - Under Gradle, `module-packaging=pom` creates an aggregator module (a minimal `build.gradle`, with no java/spring-boot plugins)
  - Maven mode reads the real `groupId`, `artifactId`, and `version` from the existing parent `pom.xml`
- `--name`: letters, digits, underscores, and hyphens only; length `5~50`; the first character must be a letter or digit
- `--group` (groupId): dotted segments (for example `com.example`). Each segment starts with a letter or digit and may then contain letters, digits, underscores, and hyphens
- `--artifact` (artifactId): letters, digits, underscores, and hyphens only, and the first character must be a letter or digit (for example `my-demo`, `demo_01`)
- `--artifact-version`: letters, digits, dots, underscores, and hyphens only, and the first character must be a letter or digit (for example `0.0.1`, `1.0.0-SNAPSHOT`)
- `--pkg` (packageName): a Java package name (for example `com.example.demo`). Dotted segments, each starting with a letter, then letters, digits, or underscores. Hyphens are not allowed
- Each name in `--modules`: length `2~50`, same rules as above. Duplicates are removed
- `--module` uses the same rules as one name in `--modules`
- `springboot create` exits with an error if the directory already exists
- `springboot module add` exits with an error if the module directory already exists or is already registered in the parent config
- `--deps` applies when:
  - Creating a single module (`springboot create` with `--packaging=jar|war`)
  - Creating a multi-module project (`springboot create` with `--packaging=pom`; applied to every `jar` module created this time)
  - Adding a module (`springboot module add` with `--packaging=pom` and `--module-packaging=jar`; applied to the new module)
- When `--module-packaging=pom`, `--deps` is ignored (an aggregator module does not write dependencies)
- Outside dry-run, every dependency ID in `--deps` is checked against the current `--boot` version. An invalid ID fails and nearby candidates are suggested

## FAQ

- The shell does not `cd` into the project afterwards?
  - The command is meant to run globally and does not change your current shell directory
  - Run `cd <project-name>` yourself

- Single-module creation fails with a download error?
  - Run `springboot boot list` and use a Boot version the current Initializr supports
  - Check that this machine can reach `https://start.spring.io` (if you set `INITIALIZR_BASE_URL`, it must point at a service compatible with the official Initializr API; only the official service is verified today)
  - Check that `curl` / `unzip` are installed and usable
  - On HTTP 400 or an invalid version, use a version from `boot list`, for example `--boot=4.0.7`

- `springboot deps list --output=web` opens the page and then says glow is missing?
  - That warning is not fatal and does not affect the page
  - Install `glow` only if you want the Markdown table rendered in the terminal

## Maintainer notes

- Shared nested-module logic lives in `lib/nested-common.sh` (path resolution, existence checks, Gradle include paths)
- Argument normalization and CSV iteration live in `lib/arg-common.sh` (shared by the entry script and the multi-module scripts)
- Dependency / Initializr interaction lives in `lib/deps.sh` (cache, Boot parameter detection, declaration extraction, deps subcommands)
- Shared module skeleton creation lives in `lib/module-template-common.sh` (`jar` and aggregator structure, class names / templates, dry-run plan fragments)
- Project-level helpers live in `lib/project-common.sh` (the shared `.gitignore` write)
- The Maven and Gradle scripts keep only build-tool differences (POM/Gradle templates and parent config updates)
- When adding nested-module behavior, change the shared script first, then the tool-specific logic in `multi-maven.sh` / `multi-gradle.sh`

Shared functions:

- `normalize_csv_unique_common`: trim CSV items, drop duplicates, keep first-seen order
- `resolve_parent_dir_common`: resolve the target parent directory (project root or `module-path`)
- `build_module_dir_common`: join the target module directory path
- `ensure_dir_exists_common`: require a directory (exit if missing)
- `ensure_file_exists_common`: require a file (exit if missing)
- `ensure_module_dir_absent_common`: reject a module directory that already exists
- `build_gradle_include_path_common`: build a Gradle include path (`a/b` -> `:a:b`)
- `iterate_csv_items_common`: iterate normalized CSV items (trim, skip empty)
- `build_package_subpath_common`: build a package subdirectory (`com.example` + `order-api` -> `com/example/order_api`)
- `create_module_scaffold_common`: create the base skeleton by module type (`jar` writes src and config, `pom` creates the directory only)
- `module_class_name`: turn a module name into a Spring Boot application class name (PascalCase + `Application`)
- `write_module_application_files`: write `*Application.java` and `*ApplicationTests.java`
- `print_jar_module_scaffold_plan_common`: dry-run plan for the shared jar module directories and templates
- `write_project_gitignore`: write the project-root `.gitignore`

## Tests

Basic bats cases and a single check script:

```bash
bash scripts/check.sh
# or tests only
bats test/springboot.bats
```

Current coverage includes:

- Basic arguments and exit codes (missing required argument, invalid bootVersion, conflicting flags)
- Core dry-run behavior (single module / Maven multi-module / Gradle multi-module)
- `modules` dedupe and normalization
- Important `module add` failures (project missing, `--module` missing)
- Conflict detection (Gradle include already present, Maven module directory already exists)
- Shared-logic regression (one `.gitignore` when creating a multi-module project)
- Network-failure regression (`deps preview` exits with the fetch-failure code)
- Maven coordinate parser fallback (`awk` when `mvn` / `xmllint` / `xmlstarlet` are unavailable)
- Nested `module-path` mounting (add a module under a nested parent)

CI workflow: `.github/workflows/ci.yml` (shellcheck + bats when a `v*` tag is pushed)

## Later (planned)

- An offline dependency mirror (cached metadata and template snippets). `INITIALIZR_BASE_URL` is reserved for a self-hosted or intranet Initializr that speaks the official API. Today only the official `https://start.spring.io` works
