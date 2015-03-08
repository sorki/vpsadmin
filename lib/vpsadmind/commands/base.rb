module VpsAdmind::Commands
  class Base
    def self.handle(type)
      VpsAdmind::Command.register(self.to_s, type)
    end

    include VpsAdmind::Utils::Command

    needs :log

    attr_accessor :output

    def initialize(cmd, params)
      @anchors = []
      @command = cmd

      params.each do |k,v|
        instance_variable_set(:"@#{k}", v)
      end

      @m_attr = Mutex.new
      @output = {}

      Thread.current[:command] = self
    end

    def exec

    end

    def rollback

    end

    def test

    end

    def post_save(db)

    end

    def step
      attrs do
        @step
      end
    end

    def step=(str)
      attrs do
        @step = str
      end
    end

    def subtask
      attrs do
        @subtask
      end
    end

    def subtask=(pid)
      attrs do
        @subtask = pid
      end
    end

    protected
    def anchor(name)
      @anchors << name
    end

    def used_anchors
      @anchors.reverse_each { |a| yield(a) }
    end

    def attrs
      ret = nil

      @m_attr.synchronize do
        ret = yield
      end

      ret
    end

    def ok
      {:ret => :ok}
    end

    # Call command +cmd+ with +opts+.
    def call_cmd(cmd, opts)
      cmd.new(@command, opts).exec
    end
  end

  module Pool        ; end
  module DatasetTree ; end
  module Branch      ; end
  module Vps         ; end
  module Dataset     ; end
  module Shaper      ; end
  module Utils       ; end
  module Mail        ; end
end
