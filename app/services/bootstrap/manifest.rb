module Bootstrap
  ##
  # The manifest file itself: load, version-check, and reject unknown sections.
  class Manifest < Data
    SCHEMA_VERSION = 1

    SECTIONS = %w[
      schema_version
      settings
      metric_clients
      log_clients
      dns
      locations
      products
      catalog
      user_group
      features
      admin_user
    ].freeze

    def self.load_file(file_path)
      unless File.exist?(file_path)
        raise Error.new("manifest not found at #{file_path}")
      end
      begin
        raw = YAML.safe_load_file(file_path, permitted_classes: [], aliases: true)
      rescue Psych::Exception => e
        raise Error.new("could not parse manifest: #{e.message}")
      end
      new(raw, "manifest")
    end

    def initialize(raw, path)
      super
      version = raw["schema_version"]
      if version.nil?
        raise Error.new("is required (this bootstrap understands schema_version #{SCHEMA_VERSION})", path: "schema_version")
      end
      unless version == SCHEMA_VERSION
        raise Error.new("unsupported value #{version.inspect}; this controller understands #{SCHEMA_VERSION}", path: "schema_version")
      end
      assert_keys!(SECTIONS)
    end
  end
end
