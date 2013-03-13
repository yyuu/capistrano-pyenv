set :application, "capistrano-pyenv"
set :repository,  "."
set :deploy_to do
  File.join("/home", user, application)
end
set :deploy_via, :copy
set :scm, :none
set :use_sudo, false
set :user, "vagrant"
set :password, "vagrant"
set :ssh_options do
  {:user_known_hosts_file => "/dev/null"}
end

role :web, "192.168.33.10"
role :app, "192.168.33.10"
role :db,  "192.168.33.10", :primary => true

$LOAD_PATH.push(File.expand_path("../../lib", File.dirname(__FILE__)))
require "capistrano-pyenv"

task(:test_all) {
  find_and_execute_task("test_default")
  find_and_execute_task("test_with_virtualenv")
  find_and_execute_task("test_without_global")
}

namespace(:test_default) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_default", "test_default:setup"
  after "test_default", "test_default:teardown"

  task(:setup) {
    find_and_execute_task("pyenv:setup")
  }

  task(:teardown) {
  }

  task(:test_pyenv) {
    run("pyenv --version")
  }

## standard
  task(:test_pyenv_exec) {
    pyenv.exec("python --version")
  }

  task(:test_run_pyenv_exec) {
    run("pyenv exec python --version")
  }

## with path
  task(:test_pyenv_exec_with_path) {
    pyenv.exec("python -c 'import os;assert os.getcwd()==\"/\"'", :path => "/")
  }

# task(:test_pyenv_exec_python_via_sudo_with_path) {
#   # capistrano does not provide safer way to invoke multiple commands via sudo.
#   pyenv.exec("python -c 'import os;assert os.getcwd()==\"/\" and os.getuid()==0'", :path => "/", :via => :sudo )
# }

## via sudo
  task(:test_pyenv_exec_via_sudo) {
    pyenv.exec("python -c 'import os;assert os.getuid()==0'", :via => :sudo)
  }

  task(:test_run_sudo_pyenv_exec) {
    # we may not be able to invoke pyenv since sudo may reset $PATH.
    # if you prefer to invoke pyenv via sudo, call it with absolute path.
#   run("#{sudo} pyenv exec python -c 'import os;assert os.getuid()==0'")
    run("#{sudo} #{pyenv_cmd} exec python -c 'import os;assert os.getuid()==0'")
  }

  task(:test_sudo_pyenv_exec) {
    sudo("#{pyenv_cmd} exec python -c 'import os;assert os.getuid()==0'")
  }

## pip
  task(:test_pyenv_exec_pip) {
    run("pyenv exec pip --version")
  }
}

namespace(:test_with_virtualenv) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_virtualenv", "test_with_virtualenv:setup"
  after "test_with_virtualenv", "test_with_virtualenv:teardown"

  task(:setup) {
    set(:pyenv_use_virtualenv, true)
    set(:pyenv_virtualenv_python_version, pyenv_python_version)
    set(:pyenv_python_version, "venv")
    find_and_execute_task("pyenv:setup")
   }

  task(:teardown) {
    set(:pyenv_use_virtualenv, false)
    set(:pyenv_python_version, pyenv_virtualenv_python_version)
    set(:pyenv_virtualenv_python_version, nil)
  }

  task(:test_pyenv_exec) {
    pyenv.exec("python --version")
  }
}

namespace(:test_without_global) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_without_global", "test_without_global:setup"
  after "test_without_global", "test_without_global:teardown"

  task(:setup) {
    version_file = File.join(pyenv_path, "version")
    run("mv -f #{version_file} #{version_file}.orig")
    set(:pyenv_setup_global_version, false)
    find_and_execute_task("pyenv:setup")
    run("test \! -f #{version_file.dump}")
  }

  task(:teardown) {
    version_file = File.join(pyenv_path, "version")
    run("mv -f #{version_file}.orig #{version_file}")
  }

## standard
  task(:test_pyenv_exec_python) {
    pyenv.exec("python --version")
  }

## with path
  task(:test_pyenv_exec_python_with_path) {
    pyenv.exec("python -c 'import os;assert os.getcwd()==\"/\"'", :path => "/")
  }

## via sudo
  task(:test_pyenv_exec_python_via_sudo) {
    pyenv.exec("python -c 'import os;assert os.getuid()==0'", :via => :sudo)
  }
}

# vim:set ft=ruby sw=2 ts=2 :
