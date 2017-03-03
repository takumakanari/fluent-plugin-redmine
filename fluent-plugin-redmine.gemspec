# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-redmine"
  spec.version       = "0.6.1"
  spec.authors       = ["Takuma kanari"]
  spec.email         = ["chemtrails.t@gmail.com"]
  spec.summary       = %q{Fluentd output plugin to create ticket in redmine}
  spec.description   = %q{Fluentd output plugin to create ticket in redmine}
  spec.homepage      = "https://github.com/takumakanari/fluent-plugin-redmine"
  spec.rubyforge_project = "fluent-plugin-redmine"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "fluentd", [">= 0.12", "< 2"]
  spec.add_development_dependency "rake"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "test-unit"
end
