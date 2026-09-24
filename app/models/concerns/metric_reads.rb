##
# Runs a batch of metric reads concurrently.
#
# Every read is an HTTP round trip to a zone's Prometheus, and the controller is
# not necessarily near the zone it is asking about -- measured from Amsterdam
# against the San Jose zone, one read is ~1.4s against ~0.05s for a zone in the
# same city. Issued in sequence, a handful of nodes' worth of reads is tens of
# seconds of page load; issued together, the whole batch costs roughly one round
# trip.
#
# Bounded on purpose. The reads are pure network waits with no useful work
# between them, so the cap exists to protect the metrics server and the process's
# thread count rather than the CPU -- an unbounded fan-out over a large fleet
# would open a socket per node per metric all at once.
#
# Every caller's read method is expected to rescue internally and return a
# neutral value, which is what keeps one slow or failing read from taking a batch
# down with it. Nothing here rescues on their behalf: `Thread#value` re-raises,
# so a read that breaks that contract surfaces to the caller rather than being
# silently turned into a zero.
module MetricReads
  # Waves of at most this many concurrent reads.
  MAX_CONCURRENCY = 12

  class << self
    # @param tasks [Hash{Object => Proc}] key => a callable performing one read
    # @return [Hash] the same keys, each mapped to its callable's return value
    def all(tasks)
      return {} if tasks.empty?

      tasks.each_slice(MAX_CONCURRENCY).flat_map { |wave| run_wave(wave) }.to_h
    end

    private

    # @param wave [Array<Array(Object, Proc)>]
    # @return [Array<Array(Object, Object)>]
    def run_wave(wave)
      threads = wave.map do |key, task|
        # executor.wrap establishes the autoload/reloader context a bare
        # Thread.new lacks, and returns any ActiveRecord connection the thread
        # leased when the block ends. Deliberately NOT with_connection: that
        # would reserve a connection for the whole round trip, and a wave of
        # twelve against a default pool of five would starve the pool while
        # every reserved connection sat idle on the network. Callers are
        # expected to have preloaded whatever their read touches.
        [key, Thread.new { Rails.application.executor.wrap { task.call } }]
      end

      # Yield this thread's share of the load interlock while blocking on the
      # children. With reloading on (development), the calling thread holds a
      # SHARED interlock; a child that triggers a Zeitwerk autoload needs the
      # EXCLUSIVE load lock, which can never be granted while we sit in
      # Thread#value still holding our share -- the request would hang forever.
      # Production eager-loads so the hook is never installed, and the test
      # environment disables reloading, so no test can catch this.
      ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
        threads.map { |key, thread| [key, thread.value] }
      end
    end
  end
end
