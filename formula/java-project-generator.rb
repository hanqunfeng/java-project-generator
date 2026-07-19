class JavaProjectGenerator < Formula
  desc "Generate Spring Boot projects quickly with shell scripts"
  homepage "https://github.com/hanqunfeng/java-project-generator"
  url "https://github.com/hanqunfeng/java-project-generator/archive/refs/tags/v1.0.8.tar.gz"
  sha256 "6ed7a32376ca2b8bb53db966e8894669cbd49f2afa8316b639f2ebced41e0f23"
  license "MIT"

  depends_on "glow"
  depends_on "pandoc"

  def install
    libexec.install "springboot"
    libexec.install "lib"
    libexec.install "completions"
    libexec.install "assets"
    (libexec/"deps-cache").mkpath

    chmod 0755, libexec/"springboot"
    Dir[libexec/"lib/*.sh"].each { |f| chmod 0755, f }

    (bin/"springboot").write <<~EOS
      #!/usr/bin/env bash
      exec "#{libexec}/springboot" "$@"
    EOS
    chmod 0755, bin/"springboot"

    bash_completion.install libexec/"completions/springboot.bash" => "springboot"
    zsh_completion.install libexec/"completions/_springboot"
  end

  def caveats
    <<~EOS
      python3 is required but NOT installed by this formula. Install before use:
        brew install python@3.13
      Needed for: deps list cache, --deps validation, and other Initializr metadata parsing.

      Optional tools (not installed by this formula):
        - jq:                 brew install jq
        - libxml2 (xmllint):  brew install libxml2
        - xmlstarlet:         brew install xmlstarlet
        - mvn:                brew install maven
      xmllint / xmlstarlet / mvn: only for Maven "module add" parent POM parsing (awk fallback still works).

      Network access to Spring Initializr is required (default: https://start.spring.io).
      Override with: export INITIALIZR_BASE_URL=<mirror-url>
    EOS
  end

  test do
    assert_match "springboot <command>", shell_output("#{bin}/springboot --help")
    assert_match "Dry-run 模式", shell_output("#{bin}/springboot create --name=brewtest --dry-run")
  end
end
