module Bootstrap
  ##
  # Every failure the bootstrap apply raises. The rake task turns it into a
  # non-zero exit with the message intact.
  #
  # +path+ is the manifest key path the failure belongs to
  # (e.g. +locations[0].regions[0].nodes[1].primary_ip+) so an operator can go
  # straight to the line in the rendered manifest.
  class Error < StandardError
    attr_reader :path

    def initialize(message, path: nil)
      @path = path
      super(path.blank? ? message : "#{path}: #{message}")
    end

    # Build an Error from a record that failed validation.
    def self.from_record(record, path:, action:)
      new("#{action} #{record.class.name} failed — #{record.errors.full_messages.join("; ")}", path: path)
    end
  end
end
