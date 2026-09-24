module Bootstrap
  ##
  # Human-readable change log for an apply. Under DRY_RUN this *is* the output:
  # everything that would change, printed, with nothing written.
  class Recorder
    REDACTED = "«redacted»".freeze

    # An address column being emptied by a readdress. See +readdress+.
    CLEARED = "(cleared)".freeze

    DRIFT_ADVICE = "manifest differs from database, database wins — " \
                   "update your inventory or change it in the UI".freeze

    attr_reader :created, :updated, :unchanged, :rotated, :linked, :skipped, :warned

    def initialize(io: $stdout, dry_run: false, update_addresses: false)
      @io = io
      @dry_run = dry_run
      @update_addresses = update_addresses
      @created = 0
      @updated = 0
      @unchanged = 0
      @rotated = 0
      @linked = 0
      @skipped = 0
      @warned = 0
      @current_section = nil
    end

    def dry_run?
      @dry_run
    end

    def update_addresses?
      @update_addresses
    end

    def header(manifest_path)
      say "ComputeStacks bootstrap apply — #{manifest_path}"
      say "DRY RUN — nothing will be written." if dry_run?
      if update_addresses?
        say "UPDATE_ADDRESSES — infrastructure addresses will be updated on rows that already exist."
      end
      say ""
    end

    def section(name)
      @current_section = name
      say "== #{name} =="
    end

    def create(subject, changes = {})
      @created += 1
      emit "create", subject, changes
    end

    def update(subject, changes = {})
      @updated += 1
      emit "update", subject, changes
    end

    def unchanged!(_subject)
      @unchanged += 1
    end

    ##
    # One credential field, on a row that already exists, brought back into
    # step with the manifest. See doc/bootstrap_manifest.md, "Exemptions from
    # bootstrap-only" — the unconditional half of that exemption.
    #
    # The value is not printed in either direction. Every field that reaches
    # here is a credential by construction, so there is nothing to show that is
    # safe to show, and "which field changed" is the whole of what an operator
    # needs from the log.
    #
    # Counts fields rather than rows, like every other counter here counts the
    # lines it emitted.
    def rotate(subject, field)
      @rotated += 1
      say format("  [%-6s] %s — %s updated (credential rotation)", "rotate", subject, field)
    end

    ##
    # One infrastructure address, on a row that already exists, brought back
    # into step with the manifest under +UPDATE_ADDRESSES=1+. See
    # doc/bootstrap_manifest.md, "Exemptions from bootstrap-only" — the
    # flag-gated half.
    #
    # Both values *are* printed, which is the difference from +rotate+. An
    # address is not a secret, and an operator who deliberately asked for a
    # readdress needs to see what moved where — this is the log a tailnet
    # rollout is checked against. A column being *emptied* prints as
    # +(cleared)+ rather than +nil+, because "the override is gone and the node
    # falls back to primary_ip" is what is being said.
    #
    # Counted as +rotated+ on purpose: the summary line is a contract with the
    # provisioner (see +summary+) and a readdress is a write of the same kind,
    # so it belongs inside the substring ansible greps rather than in a new
    # counter the provisioner is not looking at.
    def readdress(subject, field, before, after)
      @rotated += 1
      say "  [readdress] #{subject} — #{field}: #{before.inspect} -> #{after.nil? ? CLEARED : after.inspect}"
    end

    def link(subject, detail)
      @linked += 1
      emit "link", "#{subject} → #{detail}"
    end

    ##
    # A row that is already there. The bootstrap does not modify it — see
    # doc/bootstrap_manifest.md, "Apply semantics".
    def exists(subject, reason = nil)
      skip subject, reason.presence || "exists, skipped"
    end

    def skip(subject, reason)
      @skipped += 1
      emit "skip", "#{subject} (#{reason})"
    end

    ##
    # Informational only: the manifest and the database disagree about a row
    # that already exists. Nothing is written either way; this tells the
    # operator their inventory has gone stale.
    def drift(subject, changes)
      return if changes.empty?
      @warned += 1
      say format("  [%-6s] %s — %s", "warn", subject, DRIFT_ADVICE)
      changes.each do |attribute, (current, desired)|
        say "             #{attribute}: database #{current.inspect}, manifest #{desired.inspect}"
      end
    end

    ##
    # Informational only, for a row the apply declined to write for a reason of
    # its own rather than because the manifest disagreed with the database.
    # Counted with +drift+ so the summary's warning line covers both.
    def warn(subject, message)
      @warned += 1
      say format("  [%-6s] %s — %s", "warn", subject, message)
    end

    def note(message)
      say "  #{message}"
    end

    ##
    # The first line is a contract, not prose. The provisioner's
    # roles/controller_seed/tasks/main.yml sets its `changed_when` by grepping
    # stdout for the exact substring "0 created, 0 seeded, 0 rotated, 0 linked
    # were applied" — reword it and every ansible run reports "changed" for
    # ever. apply_service_test.rb pins it character for character.
    #
    # `rotated` was inserted into the middle of that substring rather than
    # appended after `linked`, because a rotation is a write and the count of
    # writes has to sit inside the string the provisioner tests for — appending
    # it would have left the old substring matching a run that rotated a
    # credential, and ansible would report "ok" for a run that changed
    # something.
    def summary
      say ""
      verb = dry_run? ? "would be" : "were"
      say "#{@created} created, #{@updated} seeded, #{@rotated} rotated, #{@linked} linked #{verb} applied; " \
          "#{@unchanged} already current, #{@skipped} skipped."
      if @warned.positive?
        say "#{@warned} row(s) were left alone — see the warnings above."
      end
      say "DRY RUN — nothing was written." if dry_run?
    end

    private

    def emit(action, subject, changes = {})
      say format("  [%-6s] %s", action, subject)
      changes.each do |attribute, (before, after)|
        say "             #{attribute}: #{before.inspect} → #{after.inspect}"
      end
    end

    def say(line)
      @io.puts line
    end
  end
end
