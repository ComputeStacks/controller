module Bootstrap
  ##
  # A hash out of the manifest, carrying its own key path so every lookup can
  # raise an error that names the offending line.
  #
  # Nothing here touches the database; it is pure manifest access + shape checks.
  class Data
    attr_reader :raw, :path

    def initialize(raw, path)
      unless raw.is_a?(Hash)
        raise Error.new("expected a mapping, got #{raw.class.name.downcase}", path: path)
      end
      @raw = raw
      @path = path
    end

    def key?(name)
      raw.key?(name.to_s)
    end

    def keys
      raw.keys
    end

    def empty?
      raw.empty?
    end

    def child_path(name)
      "#{path}.#{name}"
    end

    # Raw value, or +default+ when the key is absent or nil.
    def value(name, default = nil)
      v = raw[name.to_s]
      v.nil? ? default : v
    end

    # Raw value; raises when absent or blank.
    def fetch!(name)
      v = raw[name.to_s]
      if v.nil? || (v.respond_to?(:empty?) && v.empty?)
        raise Error.new("is required", path: child_path(name))
      end
      v
    end

    # Nested mapping, or nil.
    def child(name)
      v = raw[name.to_s]
      return nil if v.nil?
      Data.new(v, child_path(name))
    end

    # Nested list of mappings. Absent -> [].
    def children(name)
      v = raw[name.to_s]
      return [] if v.nil?
      unless v.is_a?(Array)
        raise Error.new("expected a list, got #{v.class.name.downcase}", path: child_path(name))
      end
      v.each_with_index.map { |entry, i| Data.new(entry, "#{child_path(name)}[#{i}]") }
    end

    # Nested mapping treated as a flat name => scalar hash.
    def pairs(name)
      c = child(name)
      return {} if c.nil?
      c.raw
    end

    def list(name)
      v = raw[name.to_s]
      return nil if v.nil?
      unless v.is_a?(Array)
        raise Error.new("expected a list, got #{v.class.name.downcase}", path: child_path(name))
      end
      v
    end

    # Boolean with a default, cast the way the rest of the app casts booleans.
    def flag(name, default)
      v = raw[name.to_s]
      return default if v.nil?
      ActiveModel::Type::Boolean.new.cast(v)
    end

    # Reject keys we do not understand. A typo in a generated template is far
    # more likely than a deliberate extra key, and silently ignoring it is how
    # the old bootstrap template drifted.
    def assert_keys!(allowed)
      extra = raw.keys.map(&:to_s) - allowed.map(&:to_s)
      return if extra.empty?
      raise Error.new("unknown key(s): #{extra.sort.join(", ")}", path: path)
    end

    # Collect the manifest attributes that map 1:1 onto columns. Keys absent
    # from the manifest are left out entirely so they are never written.
    def attrs(*names)
      names.each_with_object({}) do |name, h|
        key = name.to_s
        h[key] = raw[key] if raw.key?(key) && !raw[key].nil?
      end
    end
  end
end
