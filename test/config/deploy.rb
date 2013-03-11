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
  run_locally("rm -f known_hosts")
  {:user_known_hosts_file => "known_hosts"}
end

role :web, "192.168.33.10"
role :app, "192.168.33.10"
role :db,  "192.168.33.10", :primary => true

$LOAD_PATH.push(File.expand_path("../../lib", File.dirname(__FILE__)))
require "capistrano-pyenv"

namespace(:test_all) {
  task(:default) {
    find_and_execute_task("pyenv:setup")
    methods.grep(/^test_/).each do |m|
      send(m)
    end
    find_and_execute_task("pyenv:purge")
  }

  task(:test_pyenv_is_installed) {
    run("pyenv --version")
  }

  task(:test_python_is_installed) {
    run("pyenv exec python --version")
  }

  task(:test_pip_is_installed) {
    run("pyenv exec pip --version")
  }
}

# vim:set ft=ruby sw=2 ts=2 :
