module VpsAdmin
  module API
    class Param
      attr_reader :name, :label, :desc, :type

      def initialize(name, required: nil, label: nil, desc: nil, type: nil)
        @required = required
        @name = name
        @label = label || name.to_s.capitalize
        @desc = desc
        @type = type
        @layout = :custom
        @validators = {}
      end

      def required?
        @required
      end

      def optional?
        !@required
      end

      def add_validator(v)
        @validators.update(v)
      end

      def validators
        @validators
      end

      def describe
        {
            required: required?,
            label: @label,
            description: @desc,
            type: @type ? @type.to_s : String.to_s,
            validators: @validators,
        }
      end
    end

    class Params
      attr_reader :namespace, :layout

      def initialize(namespace)
        @params = []
        @namespace = namespace
        @layout = :object
      end

      def requires(*args)
        add_param(*apply(args, required: true))
      end

      def optional(*args)
        add_param(*apply(args, required: true))
      end

      def string(*args)
        add_param(*apply(args, type: String))
      end

      def id(*args)
        integer(*args)
      end

      def foreign_key(*args)
        integer(*args)
      end

      def bool(*args)
        add_param(*apply(args, type: Boolean))
      end

      def integer(*args)
        add_param(*apply(args, type: Integer))
      end

      def param(*args)
        add_param(*args)
      end

      # Action returns custom data.
      def structure(name, s)
        @namespace = name
        @layout = :custom
        @structure = s
      end

      # Action returns a list of objects.
      def list_of(name, hash)
        @namespace = name
        @layout = :list
        @structure = {name => hash}
      end

      # Action returns properties describing one object.
      def object(name, hash)
        @namespace = name
        @layout = :object
        @structure = {name => hash}
      end

      def load_validators(model)
        tr = ValidatorTranslator.new(@params)

        model.validators.each do |validator|
          tr.translate(validator)
        end
      end

      def describe
        ret = {parameters: {}}
        ret[:layout] = @layout
        ret[:namespace] = @namespace
        ret[:format] = @structure if @structure

        @params.each do |p|
          ret[:parameters][p.name] = p.describe
        end

        ret
      end

      private
        def add_param(*args)
          @params << Param.new(*args)
        end

        def apply(args, default)
          args << {} unless args.last.is_a?(Hash)
          args.last.update(default)
          args
        end
    end
  end
end
