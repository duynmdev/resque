require File.dirname(__FILE__) + '/test_helper'

context "Resque::Worker" do
  setup do
    @queue = Resque.new('localhost:6379')
    @queue.redis.flush_all

    @worker = Resque::Worker.new('localhost:6379', :jobs)
    @queue.enqueue(:jobs, SomeJob, 20, '/tmp')
  end

  test "can fail jobs" do
    @queue.enqueue(:jobs, BadJob)
    @worker.work(0)
    assert_equal 1, @queue.size("failed")
  end

  test "catches exceptional jobs" do
    @queue.enqueue(:jobs, BadJob)
    @queue.enqueue(:jobs, BadJob)
    @worker.process
    @worker.process
    @worker.process
    assert_equal 2, @queue.size("failed")
  end

  test "can work on multiple queues" do
    @queue.enqueue(:high, GoodJob)
    @queue.enqueue(:critical, GoodJob)

    worker = Resque::Worker.new('localhost:6379', :critical, :high)

    worker.process
    assert_equal 1, @queue.size(:high)
    assert_equal 0, @queue.size(:critical)

    worker.process
    assert_equal 0, @queue.size(:high)
  end

  test "has a unique id" do
    assert_equal "#{`hostname`.chomp}:#{$$}:jobs", @worker.to_s
  end

  test "complains if no queues are given" do
    assert_raise Resque::Worker::NoQueueError do
      Resque::Worker.new('localhost:6379')
    end
  end

  test "inserts itself into the 'workers' list on startup" do
    @worker.work(0) do
      assert_equal @worker.to_s, @queue.workers[0]
    end
  end

  test "removes itself from the 'workers' list on shutdown" do
    @worker.work(0) do
      assert_equal @worker.to_s, @queue.workers[0]
    end

    assert_equal [], @queue.workers
  end

  test "records what it is working on" do
    @worker.work(0) do
      task = @queue.worker(@worker.to_s)
      assert_equal({"args"=>[20, "/tmp"], "class"=>"SomeJob"}, task['payload'])
      assert task['run_at']
      assert_equal 'jobs', task['queue']
    end
  end

  test "clears its status when not working on anything" do
    @worker.work(0) do
      assert @queue.worker(@worker.to_s)
    end

    assert_equal nil, @queue.worker(@worker.to_s)
  end

  test "knows when it is working" do
    @worker.work(0) do
      assert @queue.worker(@worker.to_s)
      assert_equal :working, @queue.worker_state(@worker.to_s)
    end
  end

  test "knows when it is idle" do
    @worker.work(0) do
      assert @queue.worker(@worker.to_s)
    end
    assert_equal :idle, @queue.worker_state(@worker.to_s)
  end

  test "knows who is working" do
    @worker.work(0) do
      assert_equal [@worker.to_s], @queue.working
    end
  end

  test "keeps track of how many jobs it has processed" do
    @queue.enqueue(:jobs, BadJob)
    @queue.enqueue(:jobs, BadJob)

    3.times do
      job = @worker.reserve
      @worker.process job
    end
    assert_equal 3, @worker.processed
  end

  test "keeps track of how many failures it has seen" do
    @queue.enqueue(:jobs, BadJob)
    @queue.enqueue(:jobs, BadJob)

    3.times do
      job = @worker.reserve
      @worker.process job
    end
    assert_equal 2, @worker.failed
  end

  test "stats are erased when the worker goes away" do
    @worker.work(0)
    assert_equal 0, @worker.processed
    assert_equal 0, @worker.failed
  end

  test "knows when it started" do
    time = Time.now
    @worker.work(0) do
      assert_equal time.to_s, @queue.worker_started(@worker.to_s)
    end
  end
end
