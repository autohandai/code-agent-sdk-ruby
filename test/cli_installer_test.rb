# frozen_string_literal: true

require_relative "test_helper"

class CLIInstallerTest < SDKTestCase
  def test_binary_name_for_supported_platforms
    installer = AutohandSDK::CLIInstaller

    assert_equal("autohand-macos-arm64", installer.binary_name(host_os: "darwin", host_cpu: "arm64"))
    assert_equal("autohand-macos-x64", installer.binary_name(host_os: "darwin", host_cpu: "x86_64"))
    assert_equal("autohand-linux-arm64", installer.binary_name(host_os: "linux", host_cpu: "aarch64"))
    assert_equal("autohand-linux-x64", installer.binary_name(host_os: "linux", host_cpu: "x86_64"))
    assert_equal("autohand-windows-x64.exe", installer.binary_name(host_os: "mingw32", host_cpu: "x64"))
  end

  def test_detect_prefers_explicit_cli_path
    detected = AutohandSDK::CLIInstaller.detect(explicit_path: @cli_path, path: "")

    assert_equal(@cli_path, detected)
  end

  def test_detect_rejects_non_executable_explicit_path
    path = File.join(Dir.mktmpdir("autohand-sdk-bad-cli"), "autohand")
    File.write(path, "#!/bin/sh\n")

    error = assert_raises(AutohandSDK::ConfigurationError) do
      AutohandSDK::CLIInstaller.detect(explicit_path: path)
    end

    assert_match(/not executable/, error.message)
  ensure
    FileUtils.rm_rf(File.dirname(path)) if path
  end

  def test_detect_finds_bundled_binary
    with_bundled_cli do |root, binary|
      Dir.mktmpdir("autohand-sdk-empty") do |install_dir|
        detected = AutohandSDK::CLIInstaller.detect(root: root, install_dir: install_dir, path: "",
                                                    host_os: "darwin", host_cpu: "arm64")

        assert_equal(binary, detected)
      end
    end
  end

  def test_install_copies_bundled_binary
    with_bundled_cli do |root, source|
      Dir.mktmpdir("autohand-sdk-install") do |install_dir|
        result = AutohandSDK::CLIInstaller.install!(root: root, install_dir: install_dir, download: false,
                                                    host_os: "darwin", host_cpu: "arm64")

        assert_equal(File.join(install_dir, "autohand"), result.path)
        assert_equal("bundled", result.source)
        assert_equal(File.read(source), File.read(result.path))
        assert(File.executable?(result.path), "installed CLI should be executable")
      end
    end
  end

  def test_install_refuses_to_overwrite_different_existing_cli_without_force
    with_bundled_cli do |root, _source|
      Dir.mktmpdir("autohand-sdk-install") do |install_dir|
        destination = File.join(install_dir, "autohand")
        File.write(destination, "existing")
        FileUtils.chmod(0o755, destination)

        error = assert_raises(AutohandSDK::CLIInstallError) do
          AutohandSDK::CLIInstaller.install!(root: root, install_dir: install_dir, download: false,
                                             host_os: "darwin", host_cpu: "arm64")
        end

        assert_match(/already exists/, error.message)
      end
    end
  end

  def test_install_force_replaces_existing_cli
    with_bundled_cli do |root, source|
      Dir.mktmpdir("autohand-sdk-install") do |install_dir|
        destination = File.join(install_dir, "autohand")
        File.write(destination, "existing")
        FileUtils.chmod(0o755, destination)

        AutohandSDK::CLIInstaller.install!(root: root, install_dir: install_dir, force: true, download: false,
                                           host_os: "darwin", host_cpu: "arm64")

        assert_equal(File.read(source), File.read(destination))
      end
    end
  end

  private

  def with_bundled_cli
    Dir.mktmpdir("autohand-sdk-root") do |root|
      binary = File.join(root, "cli", "autohand-macos-arm64")
      FileUtils.mkdir_p(File.dirname(binary))
      File.write(binary, "#!/bin/sh\necho autohand\n")
      FileUtils.chmod(0o755, binary)
      yield root, binary
    end
  end
end
