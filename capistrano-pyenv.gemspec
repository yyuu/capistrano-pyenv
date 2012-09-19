# -*- encoding: utf-8 -*-
require File.expand_path('../lib/capistrano-pyenv/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Yamashita Yuu"]
  gem.email         = ["yamashita@geishatokyo.com"]
  gem.description   = %q{a capistrano recipe to manage pythons with pyenv.}
  gem.summary       = %q{a capistrano recipe to manage pythons with pyenv.}
  gem.homepage      = "https://github.com/yyuu/capistrano-pyenv"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "capistrano-pyenv"
  gem.require_paths = ["lib"]
  gem.version       = Capistrano::PyEnv::VERSION

  gem.add_dependency("capistrano")
end
