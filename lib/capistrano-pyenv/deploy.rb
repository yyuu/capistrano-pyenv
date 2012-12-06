
require "capistrano/configuration"
require "capistrano/recipes/deploy/scm"

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
            "env PYENV_VERSION=#{pyenv_python_version.dump} #{pyenv_bin}"
          }
          _cset(:pyenv_repository, 'git://github.com/yyuu/pyenv.git')
          _cset(:pyenv_branch, 'master')

          _cset(:pyenv_plugins, {
            'python-virtualenv' => 'git://github.com/yyuu/python-virtualenv.git',
          })
          _cset(:pyenv_plugins_options, {
            'python-virtualenv' => {:branch => 'master'},
          })
          _cset(:pyenv_plugins_path) {
            File.join(pyenv_path, 'plugins')
          }
          _cset(:pyenv_python_version, "2.7.3")

          _cset(:pyenv_use_virtualenv, false)
          _cset(:pyenv_virtualenv_python_version, '2.7.3')
          _cset(:pyenv_virtualenv_options, %w(--distribute --quiet --system-site-packages))

          desc("Setup pyenv.")
          task(:setup, :except => { :no_release => true }) {
            dependencies
            update
            configure
            build
          }
          after 'deploy:setup', 'pyenv:setup'

          def pyenv_update_repository(destination, options={})
            configuration = Capistrano::Configuration.new()
            options = {
              :source => proc { Capistrano::Deploy::SCM.new(configuration[:scm], configuration) },
              :revision => proc { configuration[:source].head },
              :real_revision => proc {
                configuration[:source].local.query_revision(configuration[:revision]) { |cmd| with_env("LC_ALL", "C") { run_locally(cmd) } }
              },
            }.merge(options)
            variables.merge(options).each do |key, val|
              configuration.set(key, val)
            end
            source = configuration[:source]
            revision = configuration[:real_revision]
            #
            # we cannot use source.sync since it cleans up untacked files in the repository.
            # currently we are just calling git sub-commands directly to avoid the problems.
            #
            verbose = configuration[:scm_verbose] ? nil : "-q"
            run((<<-EOS).gsub(/\s+/, ' ').strip)
              if [ -d #{destination} ]; then
                cd #{destination} &&
                #{source.command} fetch #{verbose} #{source.origin} &&
                #{source.command} fetch --tags #{verbose} #{source.origin} &&
                #{source.command} reset #{verbose} --hard #{revision};
              else
                #{source.checkout(revision, destination)};
              fi
            EOS
          end

          desc("Update pyenv installation.")
          task(:update, :except => { :no_release => true }) {
            pyenv_update_repository(pyenv_path, :scm => :git, :repository => pyenv_repository, :branch => pyenv_branch)
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
                pyenv_update_repository(File.join(pyenv_plugins_path, name), :scm => :git, :repository => repository, :branch => branch)
              }
            }
          }

          _cset(:pyenv_configure_home) { capture("echo $HOME").chomp }
          _cset(:pyenv_configure_shell) { capture("echo $SHELL").chomp }
          _cset(:pyenv_configure_files) {
            if fetch(:pyenv_configure_basenames, nil)
              [ pyenv_configure_basenames ].flatten.map { |basename|
                File.join(pyenv_configure_home, basename)
              }
            else
              bash_profile = File.join(pyenv_configure_home, '.bash_profile')
              profile = File.join(pyenv_configure_home, '.profile')
              case File.basename(pyenv_configure_shell)
              when /bash/
                [ capture("test -f #{profile.dump} && echo #{profile.dump} || echo #{bash_profile.dump}") ]
              when /zsh/
                [ File.join(pyenv_configure_home, '.zshenv') ]
              else # other sh compatible shell such like dash
                [ profile ]
              end
            end
          }
          _cset(:pyenv_configure_script) {
            (<<-EOS).gsub(/^\s*/, '')
              # Configured by capistrano-pyenv. Do not edit directly.
              export PATH="#{pyenv_path}/bin:$PATH"
              eval "$(pyenv init -)"
            EOS
          }
          _cset(:pyenv_configure_signature, '##pyenv:configure')
          task(:configure, :except => { :no_release => true }) {
            if fetch(:pyenv_use_configure, true)
              script = File.join('/tmp', "pyenv.#{$$}")
              config = [ pyenv_configure_files ].flatten
              config_map = Hash[ config.map { |f| [f, File.join('/tmp', "#{File.basename(f)}.#{$$}")] } ]
              begin
                execute = []
                put(pyenv_configure_script, script)
                config_map.each { |file, temp|
                  ## (1) copy original config to temporaly file and then modify
                  execute << "( test -f #{file} || touch #{file} )"
                  execute << "cp -fp #{file} #{temp}" 
                  execute << "sed -i -e '/^#{Regexp.escape(pyenv_configure_signature)}/,/^#{Regexp.escape(pyenv_configure_signature)}/d' #{temp}"
                  execute << "echo #{pyenv_configure_signature.dump} >> #{temp}"
                  execute << "cat #{script} >> #{temp}"
                  execute << "echo #{pyenv_configure_signature.dump} >> #{temp}"
                  ## (2) update config only if it is needed
                  execute << "cp -fp #{file} #{file}.orig"
                  execute << "( diff -u #{file} #{temp} || mv -f #{temp} #{file} )"
                }
                run(execute.join(' && '))
              ensure
                remove = [ script ] + config_map.values
                run("rm -f #{remove.join(' ')}") rescue nil
              end
            end
          }

          _cset(:pyenv_platform) {
            capture((<<-EOS).gsub(/\s+/, ' ')).strip
              if test -f /etc/debian_version; then
                if test -f /etc/lsb-release && grep -i -q DISTRIB_ID=Ubuntu /etc/lsb-release; then
                  echo ubuntu;
                else
                  echo debian;
                fi;
              elif test -f /etc/redhat-release; then
                echo redhat;
              else
                echo unknown;
              fi;
            EOS
          }
          _cset(:pyenv_python_dependencies) {
            case pyenv_platform
            when /(debian|ubuntu)/i
              %w(git-core build-essential libreadline6-dev zlib1g-dev libssl-dev)
            when /redhat/i
              %w(git-core autoconf glibc-devel patch readline readline-devel zlib zlib-devel openssl)
            else
              []
            end
          }
          task(:dependencies, :except => { :no_release => true }) {
            unless pyenv_python_dependencies.empty?
              case pyenv_platform
              when /(debian|ubuntu)/i
                run("#{sudo} apt-get install -q -y #{pyenv_python_dependencies.join(' ')}")
              when /redhat/i
                run("#{sudo} yum install -q -y #{pyenv_python_dependencies.join(' ')}")
              else
                # nop
              end
            end
          }

          desc("Build python within pyenv.")
          task(:build, :except => { :no_release => true }) {
            python = fetch(:pyenv_python_cmd, 'python')
            if pyenv_use_virtualenv
              if pyenv_virtualenv_python_version != 'system'
                # build python for virtualenv
                run("#{pyenv_bin} whence #{python} | fgrep -q #{pyenv_virtualenv_python_version} || " +
                    "#{pyenv_bin} install #{pyenv_virtualenv_python_version}")
              end
              if pyenv_python_version != 'system'
                # create virtualenv
                run("#{pyenv_bin} whence #{python} | fgrep -q #{pyenv_python_version} || " +
                    "#{pyenv_bin} virtualenv #{pyenv_virtualenv_options.join(' ')} #{pyenv_virtualenv_python_version} #{pyenv_python_version}")
              end
            else
              if pyenv_python_version != 'system'
                run("#{pyenv_bin} whence #{python} | fgrep -q #{pyenv_python_version} || #{pyenv_bin} install #{pyenv_python_version}")
              end
            end

            run("#{pyenv_cmd} exec #{python} --version && #{pyenv_cmd} global #{pyenv_python_version}")
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
