require "test_helper"
require "benchmark"

# MetricReads is pure concurrency plumbing -- no HTTP here. What matters is that
# it actually overlaps its tasks, that it stays bounded, that keys survive the
# round trip, and that it does NOT quietly swallow a task that raises (callers
# are the ones expected to rescue).
class MetricReadsTest < ActiveSupport::TestCase
  test "returns each task's value under its own key" do
    result = MetricReads.all(a: -> { 1 }, b: -> { "two" }, c: -> { nil })

    assert_equal({a: 1, b: "two", c: nil}, result)
  end

  test "keys can be arbitrary objects, not just symbols" do
    result = MetricReads.all([7, :cpu] => -> { 12.5 }, [8, :cpu] => -> { 3.0 })

    assert_equal({[7, :cpu] => 12.5, [8, :cpu] => 3.0}, result)
  end

  test "an empty batch does no work" do
    assert_equal({}, MetricReads.all({}))
  end

  test "runs its tasks concurrently rather than one after another" do
    delay = 0.3
    tasks = (1..6).index_with { |i| -> { sleep delay; i * 2 } }

    result = nil
    elapsed = Benchmark.realtime { result = MetricReads.all(tasks) }

    assert_equal (1..6).index_with { |i| i * 2 }, result
    # Sequential would be ~6 * delay. Only has to tell 0.3s from 1.8s.
    assert_operator elapsed, :<, delay * 2,
      "expected ~#{delay}s (concurrent), got #{elapsed.round(2)}s; sequential would be ~#{(delay * 6).round(2)}s"
  end

  test "never runs more than MAX_CONCURRENCY tasks at once" do
    lock = Mutex.new
    running = 0
    peak = 0
    tasks = (1..(MetricReads::MAX_CONCURRENCY * 2 + 3)).index_with do |i|
      lambda do
        lock.synchronize { running += 1; peak = [peak, running].max }
        sleep 0.05
        lock.synchronize { running -= 1 }
        i
      end
    end

    result = MetricReads.all(tasks)

    assert_equal tasks.size, result.size
    assert_operator peak, :<=, MetricReads::MAX_CONCURRENCY,
      "cap is #{MetricReads::MAX_CONCURRENCY}, saw #{peak} reads in flight"
    assert_operator peak, :>, 1, "nothing actually overlapped, so the cap proves nothing"
  end

  test "a task that raises surfaces to the caller rather than becoming a nil" do
    # Thread#value re-raises. Callers rescue in their own readers; if one stops
    # doing that, this must be loud rather than silently reported as no data.
    # Silenced only so the expected failure does not print a backtrace mid-suite.
    was = Thread.report_on_exception
    Thread.report_on_exception = false
    assert_raises(ArgumentError) do
      MetricReads.all(ok: -> { 1 }, boom: -> { raise ArgumentError, "nope" })
    end
  ensure
    Thread.report_on_exception = was
  end
end
