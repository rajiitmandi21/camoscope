class Camoscope < Formula
  desc "Investigate Mac app windows concealed from screen sharing"
  homepage "https://github.com/rajiitmandi21/camoscope"

  # TODO: fill in once a tagged release/tarball exists.
  url "https://github.com/rajiitmandi21/camoscope/archive/refs/tags/vX.Y.Z.tar.gz"
  sha256 "TODO_REPLACE_WITH_REAL_SHA256_OF_THE_RELEASE_TARBALL"
  license "MIT"

  depends_on "python@3.12"

  def install
    system Formula["python@3.12"].opt_bin/"python3.12", "-m", "pip", "install", *std_pip_args, "."
  end

  test do
    system bin/"camoscope", "--no-prompt"
  end
end
