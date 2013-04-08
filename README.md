# capistrano-pyenv

a capistrano recipe to manage pythons with [pyenv](https://github.com/yyuu/pyenv).

## Installation

Add this line to your application's Gemfile:

    gem 'capistrano-pyenv'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capistrano-pyenv

## Usage

This recipe will install [pyenv](https://github.com/yyuu/pyenv) during `deploy:setup` task.

To setup pyenv for your application, add following in you `config/deploy.rb`.

```ruby
# config/deploy.rb
require "capistrano-pyenv"
set :pyenv_python_version, "2.7.3"
```

Following options are available to manage your pyenv.

 * `:pyenv_branch` - the git branch to install `pyenv` from. use `master` by default.
 * `:pyenv_cmd` - the `pyenv` command.
 * `:pyenv_path` - the path where `pyenv` will be installed. use `$HOME/.pyenv` by default.
 * `:pyenv_plugins` - pyenv plugins to install. do nothing by default.
 * `:pyenv_repository` - repository URL of pyenv.
 * `:pyenv_python_dependencies` - depedency packages.
 * `:pyenv_python_version` - the python version to install. install `2.7.3` by default.
 * `:pyenv_use_virtualenv` - create new virtualenv from `:pyenv_virtualenv_python_version`. `false` by default. `:pyenv_python_version` will be treated as the name of the virtualenv if this is turned `true`.
 * `:pyenv_install_dependencies` - controls whether installing dependencies or not. `true` if the required packages are missing.
 * `:pyenv_setup_shell` - setup pyenv in your shell config or not. `true` by default. users who are using Chef/Puppet may prefer setting this value `false`.
 * `:pyenv_setup_default_environment` - setup `PYENV_ROOT` and update `PATH` to use pyenv over capistrano. `true` by default.
 * `:pyenv_configure_files` - list of shell configuration files to be configured for pyenv. by default, guessing from user's `$SHELL` and `$HOME`.
 * `:pyenv_configure_basenames` - advanced option for `:pyenv_configure_files`. list of filename of your shell configuration files if you don't like the default value of `:pyenv_configure_files`.
 * `:pyenv_virtualenv_python_version` - the python version to create virtualenv. `2.7.3` by default.
 * `:pyenv_virtualenv_options` - command-line options for virtualenv.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Author

- YAMASHITA Yuu (https://github.com/yyuu)
- Geisha Tokyo Entertainment Inc. (http://www.geishatokyo.com/)

## License

MIT
