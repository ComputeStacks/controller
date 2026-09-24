module Bootstrap
  ##
  # The only path the apply has to the database.
  #
  # The manifest **bootstraps** a controller; it does not converge one. So this
  # class can create a row, and it can compare a row against the manifest and
  # report the difference — but the only rows it will write to are ones nobody
  # has configured yet (+seed!+, used for the +settings+ and +features+ rows
  # that +Setting.setup!+ / +Feature.setup!+ create before any manifest exists).
  # There is no general update path: an entity that already exists is left
  # exactly as the operator left it.
  #
  # There are two enumerated exceptions, both narrow:
  #
  # * +rotate!+ — the handful of credentials the provisioner owns on *both*
  #   ends converge on every apply, unconditionally.
  # * +readdress!+ — the handful of infrastructure *addresses* the provisioner
  #   derives, converged only when the operator asked for it with
  #   +UPDATE_ADDRESSES=1+. Off by default, so the class's behaviour without
  #   that flag is unchanged.
  #
  # See their documentation, and doc/bootstrap_manifest.md, "Exemptions from
  # bootstrap-only".
  #
  # It has no destroy, no delete, and no collection-replacement method — the
  # never-destroy rule is a property of this class's API, backed by DestroyGuard
  # at the SQL level.
  #
  # Two things it gets right that a hand-rolled +find_or_create_by+ does not:
  #
  # * Only keys actually present in the manifest are considered, so an omitted
  #   key neither resets a column nor shows up as drift.
  # * Encrypted columns are compared through their *decrypted* reader.
  #   +Secret.encrypt!+ produces different ciphertext on every call, so
  #   comparing the stored value would make every secret look drifted on every
  #   run.
  class Writer
    # A column whose stored form is not its logical value.
    #
    #   desired: plaintext from the manifest (nil = key omitted, leave alone)
    #   reader:  -> { logical value or nil }
    #   writer:  ->(value) { assign, encoding as the column needs }
    Secret = Struct.new(:desired, :reader, :writer)

    def self.secret(desired, reader, writer)
      Secret.new(desired: desired, reader: reader, writer: writer)
    end

    # @param update_addresses [Boolean] whether the +addresses+ bucket converges
    #   on an existing row (+UPDATE_ADDRESSES=1+) or is only compared and
    #   drift-reported, which is the default and the behaviour that predates the
    #   flag.
    def initialize(recorder, update_addresses: false)
      @recorder = recorder
      @update_addresses = update_addresses
    end

    def update_addresses?
      @update_addresses
    end

    ##
    # Create the row if it does not exist yet; otherwise leave it completely
    # alone and report how the manifest differs from it.
    #
    # This is the entry point for every *entity* in the manifest (locations,
    # regions, nodes, networks, load balancers, clients, the DNS driver and its
    # zones, the default user group). See +create!+ for the parameters.
    #
    # +credentials+ / +credential_secrets+ are the first exception: they are
    # handed to +rotate!+, which is where the rationale lives, and they are
    # written on an existing row on every apply.
    #
    # +addresses+ is the second, and it is inert unless this Writer was built
    # with +update_addresses: true+. When it was, they are handed to
    # +readdress!+; when it was not, they are folded back into +attrs+ so they
    # are compared and drift-reported exactly as they were before the flag
    # existed.
    #
    # On a *create* neither is special: both are merged into +attrs+ /
    # +secrets+ and written like every other column. A credential is redacted on
    # the create diff by naming it in +redact+, exactly as before.
    #
    # @return [ActiveRecord::Base]
    def create_or_report!(record, label:, path:, reason: nil, attrs: {}, secrets: {}, redact: [],
      credentials: {}, credential_secrets: {}, addresses: {})
      if record.new_record?
        create!(
          record,
          label: label,
          path: path,
          attrs: attrs.merge(credentials).merge(addresses),
          secrets: secrets.merge(credential_secrets),
          redact: redact
        )
      else
        report_drift(
          record,
          label: label,
          reason: reason,
          attrs: update_addresses? ? attrs : attrs.merge(addresses),
          secrets: secrets,
          redact: redact
        )
        rotate!(record, label: label, path: path, attrs: credentials, secrets: credential_secrets)
        readdress!(record, label: label, path: path, attrs: addresses) if update_addresses?
        record
      end
    end

    ##
    # Assign and save a new record.
    #
    # @param record [ActiveRecord::Base] must be a new record
    # @param label [String] what to call it in the change log
    # @param path [String] manifest key path, used in errors
    # @param attrs [Hash{String => Object}] plain column assignments
    # @param secrets [Hash{String => Secret}] reader/writer pairs. A secret's
    #   reader/writer indirection is about *storage* (encrypt on write, decrypt
    #   to compare) — it says nothing about whether the value is sensitive. A
    #   plaintext-backed Setting is passed through `secrets:` for this same
    #   indirection and must not be redacted just for appearing here.
    # @param redact [Array<String>] names — from attrs or secrets — whose
    #   values must not be printed
    # @return [ActiveRecord::Base]
    def create!(record, label:, path:, attrs: {}, secrets: {}, redact: [])
      unless record.new_record?
        raise Error.new("#{label} already exists; the bootstrap never re-creates a row", path: path)
      end
      write!(record, label: label, path: path, attrs: attrs, secrets: secrets, redact: redact, action: "create")
    end

    ##
    # The one path that writes to a row that already exists.
    #
    # It exists because +settings+ and +features+ are not create-if-absent rows:
    # +Setting.setup!+ and +Feature.setup!+ create every one of them during
    # install, so "skip it if it exists" would mean the manifest could never
    # seed a single value. The *caller* must have established that the row is
    # still unconfigured — that judgement lives in ApplyService, not here.
    def seed!(record, label:, path:, attrs: {}, secrets: {}, redact: [])
      write!(record, label: label, path: path, attrs: attrs, secrets: secrets, redact: redact, action: "update")
    end

    ##
    # Bring the credentials on an existing row back into step with the
    # manifest. The narrow, enumerated exception to bootstrap-only.
    #
    # These are *machine-paired* values, not operator configuration. The same
    # vaulted variable that renders into the manifest also renders the server
    # side of the pair — the htpasswd file Prometheus and Loki authenticate
    # against, PowerDNS's `api-key`, the wildcard PEM on the load balancer, the
    # haproxy stats password. When one of them is rotated, the provisioner
    # converges the server and the controller's copy is the only half left
    # stale, so a green playbook run would silently leave metrics, logs, DNS or
    # the stats page broken. Nobody edits these in the admin UI in a way the
    # manifest could roll back; there is no human decision here to protect.
    #
    # It assigns *only* the fields it is given, and only those that differ. A
    # non-credential field on the same row is not touched and is still reported
    # as drift by the caller. The caller decides which fields qualify; the list
    # is enumerated in ApplyService and in doc/bootstrap_manifest.md, and this
    # method must not be handed anything else.
    #
    # Nothing is printed but the field's name — see +Recorder#rotate+.
    #
    # @return [Boolean] whether anything was written
    def rotate!(record, label:, path:, attrs: {}, secrets: {})
      rotated = []

      attrs.each do |name, desired|
        next if desired.nil?
        next if same?(record.public_send(name), desired)
        record.public_send(:"#{name}=", desired)
        rotated << name.to_s
      end

      # Compared through the decrypted reader, so a value that has not actually
      # changed is not rewritten just because its ciphertext differs.
      secrets.each do |name, spec|
        desired = spec.desired
        next if desired.nil?
        next if spec.reader.call.to_s == desired.to_s
        spec.writer.call(desired)
        rotated << name.to_s
      end

      return false if rotated.empty?

      unless record.save
        raise Error.from_record(record, path: path, action: "update")
      end

      rotated.each { |field| @recorder.rotate(label, field) }
      true
    end

    ##
    # Bring the infrastructure *addresses* on an existing row back into step
    # with the manifest. The second enumerated exception to bootstrap-only, and
    # the only one that is opt-in: this method is not reached at all unless the
    # apply was run with +UPDATE_ADDRESSES=1+.
    #
    # The fields are enumerated in ApplyService and in doc/bootstrap_manifest.md
    # ("Exemptions from bootstrap-only"); this method must not be handed
    # anything else. Deliberate topology changes — rolling tailscale onto a
    # region that is already live, moving the ACME helper or the PowerDNS API —
    # are what it exists for, which is exactly why it is not the default: the
    # same write on an ordinary run would silently roll back an address an
    # operator moved in the UI.
    #
    # Unlike +rotate!+ a +nil+ desired value is a **clear**, not "leave alone".
    # The provisioner's pairwise derivation omits +agent_host+ entirely when a
    # node and the controller are not both on the tailnet, so under this flag
    # an absent key has to mean "there is no override any more" or a rollback
    # could not be expressed at all. The caller is responsible for only putting
    # a key in this hash when absence really does mean that; +acme_server+ and
    # the DNS driver's +endpoint+ are omitted by their callers when the manifest
    # does not carry them.
    #
    # Addresses are not secrets, so both values are printed — see
    # +Recorder#readdress+.
    #
    # @return [Boolean] whether anything was written
    def readdress!(record, label:, path:, attrs: {})
      changed = []

      attrs.each do |name, desired|
        current = record.public_send(name)
        next if desired.nil? ? current.nil? : same?(current, desired)
        record.public_send(:"#{name}=", desired)
        changed << [name.to_s, current, desired]
      end

      return false if changed.empty?

      unless record.save
        raise Error.from_record(record, path: path, action: "update")
      end

      changed.each { |(field, before, after)| @recorder.readdress(label, field, before, after) }
      true
    end

    ##
    # Compare without touching anything.
    #
    # Reports the row as skipped, and — when the manifest carries values that do
    # not match what is in the database — emits an informational warning naming
    # each field. This is how a stale manifest is surfaced: the database wins,
    # and the operator is told to fix their inventory or make the change in the
    # UI.
    #
    # @return [Hash] the field-level differences (empty when there are none)
    def report_drift(record, label:, reason: nil, attrs: {}, secrets: {}, redact: [])
      differences = diff(record, attrs, secrets, redact)
      @recorder.exists(label, reason)
      @recorder.drift(label, differences) unless differences.empty?
      differences
    end

    ##
    # Add to a habtm/has_many collection. Additive only — there is deliberately
    # no method here that removes from one. Linking a *new* region to an
    # existing price or user group creates a link that was not there; it never
    # rewrites one that was.
    def link!(collection, record, label:, detail:)
      return false if collection.include?(record)
      collection << record
      @recorder.link(label, detail)
      true
    end

    private

    def write!(record, label:, path:, attrs:, secrets:, redact:, action:)
      created = record.new_record?
      redact = redact.map(&:to_s)
      changes = {}

      attrs.each do |name, desired|
        next if desired.nil?
        current = record.public_send(name)
        next if same?(current, desired)
        changes[name.to_s] = display(name, current, desired, redact)
        record.public_send(:"#{name}=", desired)
      end

      secrets.each do |name, spec|
        desired = spec.desired
        next if desired.nil?
        current = spec.reader.call
        next if current.to_s == desired.to_s
        changes[name.to_s] = display(name, current, desired, redact)
        spec.writer.call(desired)
      end

      if !created && changes.empty?
        @recorder.unchanged!(label)
        return record
      end

      unless record.save
        raise Error.from_record(record, path: path, action: action)
      end

      created ? @recorder.create(label, changes) : @recorder.update(label, changes)
      record
    end

    # The same comparison as +write!+, with every assignment removed.
    def diff(record, attrs, secrets, redact)
      redact = redact.map(&:to_s)
      changes = {}

      attrs.each do |name, desired|
        next if desired.nil?
        current = record.public_send(name)
        next if same?(current, desired)
        changes[name.to_s] = display(name, current, desired, redact)
      end

      secrets.each do |name, spec|
        desired = spec.desired
        next if desired.nil?
        current = spec.reader.call
        next if current.to_s == desired.to_s
        changes[name.to_s] = display(name, current, desired, redact)
      end

      changes
    end

    def display(name, current, desired, redact)
      if redact.include?(name.to_s)
        [current.nil? ? nil : Recorder::REDACTED, Recorder::REDACTED]
      else
        [current, desired]
      end
    end

    # Compare in the column's own terms so a YAML string never looks different
    # from the integer/boolean/array already stored.
    def same?(current, desired)
      case current
      when Array
        current.map(&:to_s).sort == Array(desired).map(&:to_s).sort
      when TrueClass, FalseClass
        current == ActiveModel::Type::Boolean.new.cast(desired)
      when Integer
        current == desired.to_i
      when Hash
        current == desired
      else
        current.to_s == desired.to_s
      end
    end
  end
end
