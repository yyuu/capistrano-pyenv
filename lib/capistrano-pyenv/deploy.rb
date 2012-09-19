module Capistrano
  module PyEnv
    def self.extended(configuration)
      configuration.load {
        namespace(:pyenv) {
          _cset(:pyenv_path) {
            capture("echo $HOME/.pyenv").chomp()
          }
          _cset(:pyenv_bin) {
            File.join(pyenv_path, 'bin', 'pyenv')
          }
          _cset(:pyenv_cmd) { # to use custom pyenv_path, we use `env` instead of cap's default_environment.
            path = "#{pyenv_path}/bin:#{pyenv_path}/shims:$PATH"
            "env PATH=#{path.dump()} #{pyenv_bin}"
          }
          _cset(:pyenv_repository, 'git://github.com/yyuu/pyenv.git')
          _cset(:pyenv_branch, 'master')

          _cset(:pyenv_plugins, {})
          _cset(:pyenv_plugins_options, {})
          _cset(:pyenv_plugins_path) {
            File.join(pyenv_path, 'plugins')
          }

          _cset(:pyenv_git) {
            if scm == :git
              if fetch(:scm_command, :default) == :default
                fetch(:git, 'git')
              else
                scm_command
              end
            else
              fetch(:git, 'git')
            end
          }

          _cset(:pyenv_python_version, '2.7.3')
          _cset(:pyenv_python_dependencies, %w(build-essential libreadline6-dev zlib1g-dev libssl-dev))

          desc("Setup pyenv.")
          task(:setup, :except => { :no_release => true }) {
            dependencies
            update
            configure
            build
          }
          after 'deploy:setup', 'pyenv:setup'

          def _pyenv_sync(repository, destination, revision)
            git = pyenv_git
            remote = 'origin'
            verbose = "-q"
            run((<<-E).gsub(/\s+/, ' '))
              if test -d #{destination}; then
                cd #{destination} && #{git} fetch #{verbose} #{remote} && #{git} fetch --tags #{verbose} #{remote} && #{git} merge #{verbose} #{remote}/#{revision};
              else
                #{git} clone #{verbose} #{repository} #{destination} && cd #{destination} && #{git} checkout #{verbose} #{revision};
              fi;
            E
          end

          desc("Update pyenv installation.")
          task(:update, :except => { :no_release => true }) {
            _pyenv_sync(pyenv_repository, pyenv_path, pyenv_branch)
            plugins.update
          }

          desc("Purge pyenv.")
          task(:purge, :except => { :no_release => true }) {
            run("rm -rf #{pyenv_path}")
          }

          namespace(:plugins) {
            desc("Update pyenv plugins.")
            task(:update, :except => { :no_release => true }) {
              pyenv_plugins.each { |name, repository|
                options = ( pyenv_plugins_options[name] || {})
                branch = ( options[:branch] || 'master' )
                _pyenv_sync(repository, File.join(pyenv_plugins_path, name), branch)
              }
            }
          }

          task(:configure, :except => { :no_release => true }) {
            # nop
          }

          task(:dependencies, :except => { :no_release => true }) {
            unless pyenv_python_dependencies.empty? # dpkg-query is faster than apt-get on querying if packages are installed
              run("dpkg-query --show #{pyenv_python_dependencies.join(' ')} 2>/dev/null || #{sudo} apt-get -y install #{pyenv_python_dependencies.join(' ')}")
            end
          }

          desc("Build python within pyenv.")
          task(:build, :except => { :no_release => true }) {
            python = fetch(:pyenv_python_cmd, 'python')
            run("#{pyenv_cmd} whence #{python} | grep -q #{pyenv_python_version} || #{pyenv_cmd} install #{pyenv_python_version}")
            run("#{pyenv_cmd} global #{pyenv_python_version} && #{pyenv_cmd} exec #{python} --version")
          }
        }
      }
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::PyEnv)
end

# vim:set ft=ruby ts=2 sw=2 :
