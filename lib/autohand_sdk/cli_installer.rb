# frozen_string_literal: true

require "digest"
require "fileutils"
require "net/http"
require "rbconfig"
require "rubygems/package"
require "securerandom"
require "tmpdir"
require "uri"
require "zlib"

require_relative "errors"
require_relative "version"

module AutohandSDK
  # rubocop:disable Metrics/ModuleLength
  module CLIInstaller
    DEFAULT_RELEASE_BASE_URL = "https://github.com/autohandai/code-cli/releases/latest/download"
    DEFAULT_INSTALL_DIR = File.join(Dir.home, ".autohand", "bin")
    MAX_REDIRECTS = 5

    InstallResult = Struct.new(:path, :source, :binary_name, :release_base_url, keyword_init: true)

    class << self
      def install!(**options)
        options = install_options(options)
        install_dir = options.fetch(:install_dir)
        force = options.fetch(:force)
        release_base_url = options.fetch(:release_base_url)
        host_os = options.fetch(:host_os)
        host_cpu = options.fetch(:host_cpu)

        binary = binary_name(host_os: host_os, host_cpu: host_cpu)
        destination = installed_binary_path(install_dir: install_dir, host_os: host_os)
        bundled = bundled_binary_path(root: options.fetch(:root), binary_name: binary, host_os: host_os)

        if bundled
          install_from_file(bundled, destination, force: force)
          return InstallResult.new(path: destination, source: "bundled", binary_name: binary,
                                   release_base_url: release_base_url)
        end

        raise CLIInstallError, missing_bundled_message(binary) unless options.fetch(:download)

        Dir.mktmpdir("autohand-cli") do |tmpdir|
          source = download_binary(binary_name: binary, release_base_url: release_base_url,
                                   checksum: options.fetch(:checksum), tmpdir: tmpdir, host_os: host_os)
          install_from_file(source, destination, force: force)
        end

        InstallResult.new(path: destination, source: "download", binary_name: binary,
                          release_base_url: release_base_url)
      end

      def detect!(explicit_path: nil, root: gem_root, install_dir: default_install_dir,
                  path: ENV.fetch("PATH", nil), host_os: self.host_os, host_cpu: self.host_cpu)
        detected = detect(explicit_path: explicit_path, root: root, install_dir: install_dir, path: path,
                          host_os: host_os, host_cpu: host_cpu)
        return detected if detected

        raise ConfigurationError, "Autohand Code CLI was not found. Run `bundle exec autohand-sdk install-cli`, " \
                                  "install `autohand` on PATH, or pass `cli_path:`."
      end

      def detect(explicit_path: nil, root: gem_root, install_dir: default_install_dir,
                 path: ENV.fetch("PATH", nil), host_os: self.host_os, host_cpu: self.host_cpu)
        return explicit_cli_path(explicit_path) if explicit_path

        binary = binary_name(host_os: host_os, host_cpu: host_cpu)
        bundled_binary_path(root: root, binary_name: binary, host_os: host_os) ||
          installed_cli_path(install_dir: install_dir, host_os: host_os) ||
          find_executable("autohand", path: path, host_os: host_os) ||
          find_executable(binary, path: path, host_os: host_os)
      end

      def status(root: gem_root, install_dir: default_install_dir, path: ENV.fetch("PATH", nil),
                 host_os: self.host_os, host_cpu: self.host_cpu)
        binary = binary_name(host_os: host_os, host_cpu: host_cpu)
        bundled = bundled_binary_path(root: root, binary_name: binary, host_os: host_os)
        installed_path = installed_binary_path(install_dir: install_dir, host_os: host_os)
        path_cli = find_executable("autohand", path: path, host_os: host_os)

        {
          sdk_version: AutohandSDK::VERSION,
          ruby_version: RUBY_VERSION,
          platform: "#{host_os}/#{host_cpu}",
          binary_name: binary,
          release_base_url: default_release_base_url,
          bundled_path: bundled,
          installed_path: installed_path,
          installed: executable_file?(installed_path, host_os: host_os),
          path_cli: path_cli,
          detected_path: detect(root: root, install_dir: install_dir, path: path, host_os: host_os,
                                host_cpu: host_cpu)
        }
      end

      def binary_name(host_os: self.host_os, host_cpu: self.host_cpu)
        os = host_os.to_s.downcase
        cpu = host_cpu.to_s.downcase

        case os
        when /darwin/
          arm_cpu?(cpu) ? "autohand-macos-arm64" : "autohand-macos-x64"
        when /linux/
          arm_cpu?(cpu) ? "autohand-linux-arm64" : "autohand-linux-x64"
        when /mswin|mingw|cygwin/
          "autohand-windows-x64.exe"
        else
          raise ConfigurationError, "Unsupported platform: #{os}/#{cpu}"
        end
      end

      def bundled_binary_path(root: gem_root, binary_name: self.binary_name, host_os: self.host_os)
        path = File.expand_path(File.join("cli", binary_name), root)
        executable_file?(path, host_os: host_os) ? path : nil
      end

      def installed_binary_path(install_dir: default_install_dir, host_os: self.host_os)
        File.expand_path(File.join(install_dir, windows?(host_os) ? "autohand.exe" : "autohand"))
      end

      def find_executable(name, path: ENV.fetch("PATH", nil), host_os: self.host_os)
        path.to_s.split(File::PATH_SEPARATOR).each do |directory|
          candidate = File.join(directory, name)
          return candidate if executable_file?(candidate, host_os: host_os)
        end

        nil
      end

      def default_release_base_url
        ENV.fetch("AUTOHAND_CLI_RELEASE_BASE_URL", DEFAULT_RELEASE_BASE_URL)
      end

      def default_install_dir
        ENV.fetch("AUTOHAND_CLI_INSTALL_DIR", DEFAULT_INSTALL_DIR)
      end

      def gem_root
        File.expand_path("../..", __dir__)
      end

      private

      def install_options(options)
        {
          install_dir: default_install_dir,
          force: false,
          release_base_url: default_release_base_url,
          checksum: ENV.fetch("AUTOHAND_CLI_SHA256", nil),
          root: gem_root,
          download: true,
          host_os: host_os,
          host_cpu: host_cpu
        }.merge(options)
      end

      def host_os
        RbConfig::CONFIG.fetch("host_os")
      end

      def host_cpu
        RbConfig::CONFIG.fetch("host_cpu")
      end

      def explicit_cli_path(path)
        expanded = File.expand_path(path.to_s)
        return expanded if executable_file?(expanded)

        raise ConfigurationError, "Configured Autohand CLI path is not executable: #{expanded}"
      end

      def installed_cli_path(install_dir:, host_os:)
        path = installed_binary_path(install_dir: install_dir, host_os: host_os)
        executable_file?(path, host_os: host_os) ? path : nil
      end

      def arm_cpu?(cpu)
        cpu.include?("arm") || cpu.include?("aarch64")
      end

      def windows?(host_os)
        host_os.to_s.downcase.match?(/mswin|mingw|cygwin/)
      end

      def executable_file?(path, host_os: self.host_os)
        return false if path.to_s.empty? || !File.file?(path)

        windows?(host_os) || File.executable?(path)
      end

      def missing_bundled_message(binary)
        "No bundled Autohand CLI binary was found for #{binary}. " \
          "Allow downloads or set AUTOHAND_CLI_RELEASE_BASE_URL to a release asset base URL."
      end

      def download_binary(binary_name:, release_base_url:, checksum:, tmpdir:, host_os:)
        asset = asset_name(binary_name, host_os: host_os)
        archive_path = File.join(tmpdir, asset)
        download_file(asset_url(release_base_url, asset), archive_path)

        expected_checksum = checksum || fetch_remote_checksum(release_base_url, asset)
        verify_checksum(archive_path, expected_checksum) if expected_checksum

        if asset.end_with?(".tar.gz")
          extract_tar_gz(archive_path, binary_name, tmpdir, host_os: host_os)
        else
          FileUtils.chmod(0o755, archive_path) unless windows?(host_os)
          archive_path
        end
      end

      def asset_name(binary_name, host_os:)
        return binary_name if windows?(host_os)

        "#{binary_name}.tar.gz"
      end

      def asset_url(release_base_url, asset)
        URI("#{release_base_url.to_s.chomp("/")}/#{asset}")
      end

      def download_file(uri, destination, redirects: MAX_REDIRECTS)
        request(uri, redirects: redirects) do |response|
          File.open(destination, "wb") do |file|
            response.read_body { |chunk| file.write(chunk) }
          end
        end
      rescue SystemCallError => e
        raise CLIInstallError, "Failed to write downloaded CLI asset to #{destination}: #{e.message}"
      end

      def fetch_remote_checksum(release_base_url, asset)
        uri = asset_url(release_base_url, "#{asset}.sha256")
        body = +""
        request(uri) { |response| response.read_body { |chunk| body << chunk } }
        body.split(/\s+/).find { |part| part.match?(/\A\h{64}\z/) }
      rescue CLIInstallError
        nil
      end

      def request(uri, redirects: MAX_REDIRECTS, &block)
        raise CLIInstallError, "Too many redirects while downloading #{uri}" if redirects.negative?

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(Net::HTTP::Get.new(uri)) do |response|
            case response
            when Net::HTTPSuccess
              return block.call(response)
            when Net::HTTPRedirection
              location = response["location"]
              raise CLIInstallError, "Redirect from #{uri} did not include a location" if location.to_s.empty?

              return request(URI(location), redirects: redirects - 1, &block)
            else
              raise CLIInstallError, "Failed to download #{uri}: #{response.code} #{response.message}"
            end
          end
        end
      rescue URI::InvalidURIError, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
        raise CLIInstallError, "Failed to download #{uri}: #{e.class}: #{e.message}"
      end

      def verify_checksum(path, expected)
        expected = expected.to_s.downcase
        actual = Digest::SHA256.file(path).hexdigest
        return if actual == expected

        raise CLIInstallError, "Checksum mismatch for #{File.basename(path)}: expected #{expected}, got #{actual}"
      end

      def extract_tar_gz(archive_path, binary_name, tmpdir, host_os:)
        destination = File.join(tmpdir, binary_name)
        entry_names = [binary_name, windows?(host_os) ? "autohand.exe" : "autohand"]

        Zlib::GzipReader.open(archive_path) do |gzip|
          Gem::Package::TarReader.new(gzip) do |tar|
            tar.each do |entry|
              next unless entry.file? && entry_names.include?(File.basename(entry.full_name))

              File.open(destination, "wb") do |file|
                while (chunk = entry.read(16 * 1024))
                  file.write(chunk)
                end
              end
              FileUtils.chmod(0o755, destination)
              return destination
            end
          end
        end

        raise CLIInstallError, "Downloaded archive did not contain #{entry_names.join(" or ")}"
      rescue Gem::Package::TarInvalidError, Zlib::GzipFile::Error => e
        raise CLIInstallError, "Failed to extract #{File.basename(archive_path)}: #{e.message}"
      end

      def install_from_file(source, destination, force:)
        if File.exist?(destination) && !force
          return destination if same_file_content?(source, destination)

          raise CLIInstallError, "#{destination} already exists. Re-run with --force to replace it."
        end

        FileUtils.mkdir_p(File.dirname(destination))
        tmp_destination = "#{destination}.#{SecureRandom.hex(8)}.tmp"
        FileUtils.cp(source, tmp_destination)
        FileUtils.chmod(0o755, tmp_destination)
        FileUtils.mv(tmp_destination, destination)
        destination
      ensure
        FileUtils.rm_f(tmp_destination) if tmp_destination
      end

      def same_file_content?(left, right)
        Digest::SHA256.file(left).hexdigest == Digest::SHA256.file(right).hexdigest
      rescue SystemCallError
        false
      end
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
