# frozen_string_literal: true

module AutohandSDK
  class EventQueue
    def initialize
      @items = []
      @mutex = Mutex.new
      @condition = ConditionVariable.new
    end

    def push(item)
      @mutex.synchronize do
        @items << item
        @condition.signal
      end
    end

    def pop(timeout: nil)
      deadline = timeout && (Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout)

      @mutex.synchronize do
        while @items.empty?
          if deadline
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            return nil if remaining <= 0

            @condition.wait(@mutex, remaining)
          else
            @condition.wait(@mutex)
          end
        end

        @items.shift
      end
    end

    def clear
      @mutex.synchronize { @items.clear }
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
