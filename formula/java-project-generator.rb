class JavaProjectGenerator < Formula
  desc "Generate Spring Boot projects quickly with shell scripts"
  homepage "https://github.com/hanqunfeng/java-project-generator"
  url "https://github.com/hanqunfeng/java-project-generator/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "b81d5cc3902fbf6b7a5cf0386ca406ee7404f040937240d9e4607515229e1209"
  license "MIT"

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

  test do
    assert_match "springboot <command>", shell_output("#{bin}/springboot --help")
  end
end
