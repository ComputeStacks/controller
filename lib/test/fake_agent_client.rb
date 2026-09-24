# Recording test double for Agent::Client — the model/service-level alternative to
# WebMock.
#
# `test/services/agent/client_test.rb` exercises the real HTTP client with WebMock scoped
# to that one class (enabling WebMock process-wide would block the real HTTP other suites
# make). Everything ABOVE the client — Volume#create_backup!, VolumeServices::CloneStepService,
# the clone workers — has no business asserting on wire shape, so it substitutes this double
# instead:
#
#     fake = FakeAgentClient.new
#     Agent::Client.stub(:for_node, fake) { @volume.create_backup!("snap") }
#     fake.calls_of(:create_task).first[1][:name] # => "volume.backup"
#
# The recorded shape is `[method_symbol, *positional_args]`, so a call is destructured the
# same way it is written. Keyword-only methods (#changelog) record a single Hash.
#
# IMPORTANT: the signatures below MUST track app/services/agent/client.rb exactly. A double
# that drifts from the real method's arity passes tests that would crash in production.
class FakeAgentClient
  # method name => canned return value. `:echo` is #create_task's default: the real 202
  # response echoes the controller-supplied id back, and Volume#dispatch_task! returns it.
  DEFAULT_RETURNS = {
    provision_tenant!: true,
    deprovision_tenant!: true,
    put_managed: true,
    get_db: "",
    all_db: "",
    changelog: [],
    ack_changelog: true,
    put_firewall_rules: true,
    delete_firewall_rules: true,
    put_volume: true,
    delete_volume: true,
    create_task: :echo
  }.freeze

  # @return [Array<Array>] every recorded call, in order, as [kind, *args]
  attr_reader :calls

  # Mirrors Agent::Client's readers so code that inspects the client still works.
  attr_reader :node, :project

  # @param node [Node, nil] cosmetic; only for callers that read client.node
  # @param project [Deployment, nil] cosmetic; only for callers that read client.project
  # @param fail_create_task_on [Integer, Array<Integer>, nil] 1-based ordinals of #create_task
  #   calls that must return false regardless of the canned return. `fail_create_task_on: 1`
  #   makes the first dispatch fail and every retry after it succeed.
  # @param returns [Hash] per-method canned return values, e.g. `create_task: false` (the
  #   un-backfilled-node / reserved-id refusal) or `put_volume: false` (self-heal failure,
  #   which aborts dispatch_task! before the POST). A value that responds to #call is invoked
  #   with the method's arguments, for tests that need a per-call decision.
  def initialize(node: nil, project: nil, fail_create_task_on: nil, **returns)
    unknown = returns.keys - DEFAULT_RETURNS.keys
    raise ArgumentError, "FakeAgentClient: unknown method(s) #{unknown.inspect}" if unknown.any?

    @node = node
    @project = project
    @calls = []
    @returns = DEFAULT_RETURNS.merge(returns)
    @fail_create_task_on = Array(fail_create_task_on).map(&:to_i)
    # Counted independently of @calls so clearing the recording never shifts the schedule.
    @create_task_count = 0
  end

  # --- tenant / managed blobs -----------------------------------------------------

  def provision_tenant!
    record(:provision_tenant!)
  end

  def deprovision_tenant!
    record(:deprovision_tenant!)
  end

  def put_managed(path, body)
    record(:put_managed, path, body)
  end

  def get_db(path)
    record(:get_db, path)
  end

  def all_db
    record(:all_db)
  end

  # --- changelog (up-channel) -----------------------------------------------------

  # Keyword-only on the real client, so the recorded call is [:changelog, Hash].
  def changelog(since:, entity_type: nil, limit: 1000)
    record(:changelog, {since: since, entity_type: entity_type, limit: limit})
  end

  def ack_changelog(seq)
    record(:ack_changelog, seq)
  end

  # --- DOWN endpoints (desired state) ---------------------------------------------

  def put_firewall_rules(host, rules)
    record(:put_firewall_rules, host, rules)
  end

  def delete_firewall_rules(host)
    record(:delete_firewall_rules, host)
  end

  def put_volume(project_id, name, desired)
    record(:put_volume, project_id, name, desired)
  end

  def delete_volume(project_id, name)
    record(:delete_volume, project_id, name)
  end

  # The real client returns the task id (truthy) on a 202 and `false` on refusal/failure.
  # @param body [Hash] {id, project_id, name, node, volume, archive, audit_id, params}
  # @return [String, false]
  def create_task(body)
    @calls << [:create_task, body]
    @create_task_count += 1
    return false if @fail_create_task_on.include?(@create_task_count)

    value = @returns[:create_task]
    return value.call(body) if value.respond_to?(:call)
    (value == :echo) ? (body[:id] || body["id"]) : value
  end

  # --- inspection -----------------------------------------------------------------

  # @param kind [Symbol] e.g. :create_task
  # @return [Array<Array>] the matching recorded calls, still as [kind, *args]
  def calls_of(kind)
    @calls.select { |c| c.first == kind }
  end

  # @return [Array, nil] the most recent call of `kind`
  def last_call(kind)
    calls_of(kind).last
  end

  def called?(kind)
    calls_of(kind).any?
  end

  # Every task body POSTed, in order.
  # @return [Array<Hash>]
  def task_bodies
    calls_of(:create_task).map { |c| c[1] }
  end

  # Task bodies for one task name, e.g. "volume.backup" / "volume.restore".
  # @return [Array<Hash>]
  def tasks_named(name)
    task_bodies.select { |b| (b[:name] || b["name"]).to_s == name.to_s }
  end

  # Forget everything recorded so far. Canned returns are untouched, and the
  # `fail_create_task_on` ordinals keep counting from where they were — clearing the
  # recording must not silently re-arm a failure that already fired.
  # @return [self]
  def reset!
    @calls.clear
    self
  end
  alias_method :clear, :reset!

  private

  def record(kind, *args)
    @calls << [kind, *args]
    value = @returns[kind]
    value.respond_to?(:call) ? value.call(*args) : value
  end
end
