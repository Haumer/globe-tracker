# Provide Object#stub if minitest/mock is unavailable (Ruby 3.3+ bundled gems issue).
# This mirrors the Minitest stub API: obj.stub(:method, val_or_callable) { ... }
unless Object.method_defined?(:stub)
  class Object
    def stub(method_name, val_or_callable, *_block_args)
      metaclass = singleton_class
      original = method(method_name)

      if val_or_callable.respond_to?(:call)
        metaclass.define_method(method_name) { |*a, **kw, &b| val_or_callable.call(*a, **kw, &b) }
      else
        metaclass.define_method(method_name) { |*_a, **_kw, &_b| val_or_callable }
      end

      yield
    ensure
      metaclass.define_method(method_name, original)
    end
  end
end
