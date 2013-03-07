require "capistrano-pyenv/version"
require "capistrano/configuration"
require "capistrano/recipes/deploy/scm"

module Capistrano
  module PyEnv
    def self.extended(configuration)
      configuration.load {
        namespace(:pyenv) {
          _cset(:pyenv_root, "$HOME/.pyenv")
          _cset(:pyenv_path) {
            # expand to actual path to use this value since pyenv may be executed by users other than `:user`.
            capture("echo #{pyenv_root.dump}").strip
          }
          _cset(:pyenv_bin_path) { File.join(pyenv_path, "bin") }
          _cset(:pyenv_shims_path) { File.join(pyenv_path, "shims") }
          _cset(:pyenv_bin) {
            File.join(pyenv_bin_path, "pyenv")
          }
          _cset(:pyenv_cmd) {
            "env PYENV_VERSION=#{pyenv_python_version.dump} #{pyenv_bin}"
          }
          _cset(:pyenv_repository, 'git://github.com/yyuu/pyenv.git')
          _cset(:pyenv_branch, 'master')

          _cset(:pyenv_plugins) {{
            "pyenv-virtualenv" => { :repository => "git://github.com/yyuu/pyenv-virtualenv.git", :branch => "master" },
          }}
          _cset(:pyenv_plugins_options, {}) # for backward compatibility. plugin options can be configured from :pyenv_plugins.
          _cset(:pyenv_plugins_path) {
            File.join(pyenv_path, 'plugins')
          }
          _cset(:pyenv_python_version, "2.7.3")

          _cset(:pyenv_use_virtualenv, false)
          _cset(:pyenv_virtualenv_python_version, '2.7.3')
          _cset(:pyenv_virtualenv_options, %w(--distribute --quiet --system-site-packages))

          _cset(:pyenv_install_dependencies, true)

          desc("Setup pyenv.")
          task(:setup, :except => { :no_release => true }) {
            dependencies if pyenv_install_dependencies
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

          def setup_default_environment
            env = fetch(:default_environment, {}).dup
            env["PYENV_ROOT"] = pyenv_path
            env["PATH"] = [ pyenv_shims_path, pyenv_bin_path, env.fetch("PATH", "$PATH") ].join(":")
            set(:default_environment, env)
          end

          _cset(:pyenv_define_default_environment, true)
          # workaround for `multistage` of capistrano-ext.
          # https://github.com/yyuu/capistrano-rbenv/pull/5
          if top.namespaces.key?(:multistage)
            after "multistage:ensure" do
              setup_default_environment if pyenv_define_default_environment
            end
          else
            on :start do
              setup_default_environment if pyenv_define_default_environment
            end
          end

          desc("Purge pyenv.")
          task(:purge, :except => { :no_release => true }) {
            run("rm -rf #{pyenv_path.dump}")
          }

          namespace(:plugins) {
            desc("Update pyenv plugins.")
            task(:update, :except => { :no_release => true }) {
              pyenv_plugins.each do |name, repository|
                # for backward compatibility, obtain plugin options from :pyenv_plugins_options first
                options = pyenv_plugins_options.fetch(name, {})
                options = options.merge(Hash === repository ? repository : {:repository => repository})
                pyenv_update_repository(File.join(pyenv_plugins_path, name), options.merge(:scm => :git))
              end
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
                [ capture("test -f #{profile.dump} && echo #{profile.dump} || echo #{bash_profile.dump}").chomp ]
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
              export PATH=#{[ pyenv_bin_path, "$PATH"].join(":").dump}
              eval "$(pyenv init -)"
            EOS
          }

          def _update_config(script_file, file, tempfile)
            execute = []
            ## (1) ensure copy source file exists
            execute << "( test -f #{file.dump} || touch #{file.dump} )"
            ## (2) copy originao config to temporary file
            execute << "rm -f #{tempfile.dump}" # remove tempfile to preserve permissions of original file
            execute << "cp -fp #{file.dump} #{tempfile.dump}" 
            ## (3) modify temporary file
            execute << "sed -i -e '/^#{Regexp.escape(pyenv_configure_signature)}/,/^#{Regexp.escape(pyenv_configure_signature)}/d' #{tempfile.dump}"
            execute << "echo #{pyenv_configure_signature.dump} >> #{tempfile.dump}"
            execute << "cat #{script_file.dump} >> #{tempfile.dump}"
            execute << "echo #{pyenv_configure_signature.dump} >> #{tempfile.dump}"
            ## (4) update config only if it is needed
            execute << "cp -fp #{file.dump} #{(file + ".orig").dump}"
            execute << "( diff -u #{file.dump} #{tempfile.dump} || mv -f #{tempfile.dump} #{file.dump} )"
            run(execute.join(" && "))
          end

          def update_config(script_file, file)
            begin
              tempfile = capture("mktemp /tmp/pyenv.XXXXXXXXXX").strip
              _update_config(script_file, file, tempfile)
            ensure
              run("rm -f #{tempfile.dump}") rescue nil
            end
          end

          _cset(:pyenv_configure_signature, '##pyenv:configure')
          task(:configure, :except => { :no_release => true }) {
            if fetch(:pyenv_use_configure, true)
              begin
                script_file = capture("mktemp /tmp/pyenv.XXXXXXXXXX").strip
                top.put(pyenv_configure_script, script_file)
                [ pyenv_configure_files ].flatten.each do |file|
                  update_config(script_file, file)
                end
              ensure
                run("rm -f #{script_file.dump}") rescue nil
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
                begin
                  run("dpkg-query -s #{pyenv_python_dependencies.join(' ')} > /dev/null")
                rescue
                  run("#{sudo} apt-get install -q -y #{pyenv_python_dependencies.join(' ')}")
                end
              when /redhat/i
                begin
                  run("rpm -qi #{pyenv_python_dependencies.join(' ')} > /dev/null")
                rescue
                  run("#{sudo} yum install -q -y #{pyenv_python_dependencies.join(' ')}")
                end
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

          # call `pyenv rehash` to update shims.
          def rehash()
            run("#{pyenv_cmd} rehash")
          end
        }
      }
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::PyEnv)
end

# vim:set ft=ruby ts=2 sw=2 :
