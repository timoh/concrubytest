require 'concurrent'
require 'rest-client'
require 'json'
require 'benchmark'
require 'benchmark/ips'

def get_random_page
  url = "https://www.mediawiki.org/api/rest_v1/page/random/summary"
  resp = RestClient.get url
  JSON.parse resp
end

def latched_get(latch = nil)
  if latch
    get_random_page
    latch.count_down
  end
end

def benchmark(page_count=25)
  Benchmark.ips do |bm|

    # No kind of concurrence
    bm.report("sequential") do
      latch = Concurrent::CountDownLatch.new(page_count)
      page_count.times { latched_get(latch) }
      latch.wait
    end

    # Using futures without fixing the thread pool size..
    # ..thus possibly having more scheduler overhead (see below)
    bm.report("future") do
      latch = Concurrent::CountDownLatch.new(page_count)
      page_count.times { Concurrent::Future.execute { latched_get(latch) } }
      latch.wait
    end

    # according to this article: http://jerrydantonio.com/actors-futures-and-concurrent-io/
    # ..fixing the thread pool can speed things up because:
    # "There are diminishing returns to adding new threads as additional resources..
    # .. are consumed and the scheduler has to work harder."
    bm.report("future_fixpool") do
      pool = Concurrent::FixedThreadPool.new(100)
      latch = Concurrent::CountDownLatch.new(page_count)
      page_count.times { Concurrent::Future.execute(executor: pool) { latched_get(latch) } }
      latch.wait
    end

    bm.compare!
  end
end

puts ""
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Benchmark with TEN"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts ""
benchmark(10)

puts ""
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Benchmark with FIDDY"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts ""
benchmark(50)

puts ""
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Benchmark with ONE HUNNID"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts ""
benchmark(100)

#
# Should yield something like:
#
# ...
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Benchmark with ONE HUNNID
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Warming up --------------------------------------
#           sequential     1.000  i/100ms
#               future     1.000  i/100ms
#       future_fixpool     1.000  i/100ms
# Calculating -------------------------------------
#           sequential      0.017  (± 0.0%) i/s -      1.000  in  57.234799s
#               future      0.351  (± 0.0%) i/s -      2.000  in   5.752248s
#       future_fixpool      0.356  (± 0.0%) i/s -      2.000  in   5.624366s
#
# Comparison:
#       future_fixpool:        0.4 i/s
#               future:        0.4 i/s - 1.01x  slower
#           sequential:        0.0 i/s - 20.36x  slower
