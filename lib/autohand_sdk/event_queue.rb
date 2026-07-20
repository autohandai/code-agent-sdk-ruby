# frozen_string_literal: true

module AutohandSDK
  class EventQueue
    DEFAULT_LIMIT = 1_024

    def initialize(limit: DEFAULT_LIMIT)
      raise ArgumentError, "event queue limit must be positive" unless limit.positive?

      @limit = limit
      @items = []
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @closed = false
    end

    def push(item)
      @mutex.synchronize do
        return if @closed

        @items << item
        @items.shift while @items.length > @limit
        @condition.signal
      end
    end

    def pop(timeout: nil)
      deadline = timeout && (Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout)

      @mutex.synchronize do
        while @items.empty? && !@closed
          if deadline
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            return nil if remaining <= 0

            @condition.wait(@mutex, remaining)
          else
            @condition.wait(@mutex)
          end
        end

        @items.shift unless @items.empty?
      end
    end

    def close
      @mutex.synchronize do
        @closed = true
        @condition.broadcast
      end
    end

    def closed?
      @mutex.synchronize { @closed }
    end

    def clear
      @mutex.synchronize { @items.clear }
    end

    def size
      @mutex.synchronize { @items.size }
    end

    def drain
      @mutex.synchronize do
        items = @items.dup
        @items.clear
        items
      end
    end
  end
end
