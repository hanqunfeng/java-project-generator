class JavaProjectGenerator < Formula
  desc "Generate Spring Boot projects quickly with shell scripts"
  homepage "https://github.com/hanqunfeng/java-project-generator"
  url "https://github.com/hanqunfeng/java-project-generator/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "6db7dfa98891f4cadce84c9354a31e49884d6a92626b8799fed4205795badec2"
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
