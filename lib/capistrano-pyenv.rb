require "capistrano-pyenv/version"
require "capistrano/configuration"
require "capistrano/configuration/resources/platform_resources"
require "capistrano/recipes/deploy/scm"

module Capistrano
  module PyEnv
    def self.extended(configuration)
      configuration.load {
        namespace(:pyenv) {
          _cset(:pyenv_root, "$HOME/.pyenv")
          _cset(:pyenv_path) {
            # expand to actual path since pyenv may be executed by users other than `:user`.
            capture("echo #{pyenv_root.dump}").strip
          }
          _cset(:pyenv_bin_path) { File.join(pyenv_path, "bin") }
          _cset(:pyenv_shims_path) { File.join(pyenv_path, "shims") }
          _cset(:pyenv_bin) {
            File.join(pyenv_bin_path, "pyenv")
          }
          def pyenv_command(options={})
            environment = _merge_environment(pyenv_environment, options.fetch(:env, {}))
            environment["PYENV_VERSION"] = options[:version] if options.key?(:version)
            if environment.empty?
              pyenv_bin
            else
              env = (["env"] + environment.map { |k, v| "#{k}=#{v.dump}" }).join(" ")
              "#{env} #{pyenv_bin}"
            end
          end
          _cset(:pyenv_cmd) { pyenv_command(:version => pyenv_python_version) } # this declares PYENV_VERSION.
          _cset(:pyenv_environment) {{
            "PYENV_ROOT" => pyenv_path,
            "PATH" => [ pyenv_shims_path, pyenv_bin_path, "$PATH" ].join(":"),
          }}
          _cset(:pyenv_repository, "https://github.com/yyuu/pyenv.git")
          _cset(:pyenv_branch, "master")

          _cset(:pyenv_plugins) {{
            "pyenv-virtualenv" => { :repository => "https://github.com/yyuu/pyenv-virtualenv.git", :branch => "master" },
          }}
          _cset(:pyenv_plugins_options, {}) # for backward compatibility. plugin options can be configured from :pyenv_plugins.
          _cset(:pyenv_plugins_path) {
            File.join(pyenv_path, 'plugins')
          }
          _cset(:pyenv_python_version, "2.7.3")

          _cset(:pyenv_use_virtualenv, false)
          _cset(:pyenv_virtualenv_python_version, "2.7.3")
          _cset(:pyenv_virtualenv_options, %w(--distribute --quiet --system-site-packages))

          _cset(:pyenv_install_dependencies) {
            if pyenv_python_dependencies.empty?
              false
            else
              not(platform.packages.installed?(pyenv_python_dependencies))
            end
          }

          desc("Setup pyenv.")
          task(:setup, :except => { :no_release => true }) {
            #
            # skip installation if the requested version has been installed.
            #
            reset!(:pyenv_python_versions)
            begin
              installed = pyenv_python_versions.include?(pyenv_python_version)
            rescue
              installed = false
            end
            _setup unless installed
            configure if pyenv_setup_shell
            pyenv.global(pyenv_python_version) if fetch(:pyenv_setup_global_version, true)
          }
          after "deploy:setup", "pyenv:setup"

          task(:_setup, :except => { :no_release => true }) {
            dependencies if pyenv_install_dependencies
            update
            build
          }

          def _update_repository(destination, options={})
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
            _update_repository(pyenv_path, :scm => :git, :repository => pyenv_repository, :branch => pyenv_branch)
            plugins.update
          }

          _cset(:pyenv_setup_default_environment) {
            if exists?(:pyenv_define_default_environment)
              logger.info(":pyenv_define_default_environment has been deprecated. use :pyenv_setup_default_environment instead.")
              fetch(:pyenv_define_default_environment, true)
            else
              true
            end
          }
          # workaround for loading `capistrano-rbenv` later than `capistrano/ext/multistage`.
          # https://github.com/yyuu/capistrano-rbenv/pull/5
          if top.namespaces.key?(:multistage)
            after "multistage:ensure", "pyenv:setup_default_environment"
          else
            on :load do
              if top.namespaces.key?(:multistage)
                # workaround for loading `capistrano-rbenv` earlier than `capistrano/ext/multistage`.
                # https://github.com/yyuu/capistrano-rbenv/issues/7
                after "multistage:ensure", "pyenv:setup_default_environment"
              else
                setup_default_environment
              end
            end
          end

          _cset(:pyenv_environment_join_keys, %w(DYLD_LIBRARY_PATH LD_LIBRARY_PATH MANPATH PATH))
          def _merge_environment(x, y)
            x.merge(y) { |key, x_val, y_val|
              if pyenv_environment_join_keys.include?(key)
                ( y_val.split(":") + x_val.split(":") ).uniq.join(":")
              else
                y_val
              end
            }
          end

          task(:setup_default_environment, :except => { :no_release => true }) {
            if pyenv_setup_default_environment
              set(:default_environment, _merge_environment(default_environment, pyenv_environment))
            end
          }

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
                _update_repository(File.join(pyenv_plugins_path, name), options.merge(:scm => :git))
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

          def _do_update_config(script_file, file, tempfile)
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

          def _update_config(script_file, file)
            begin
              tempfile = capture("mktemp /tmp/pyenv.XXXXXXXXXX").strip
              _do_update_config(script_file, file, tempfile)
            ensure
              run("rm -f #{tempfile.dump}") rescue nil
            end
          end

          _cset(:pyenv_setup_shell) {
            if exists?(:pyenv_use_configure)
              logger.info(":pyenv_use_configure has been deprecated. please use :pyenv_setup_shell instead.")
              fetch(:pyenv_use_configure, true)
            else
              true
            end
          }
          _cset(:pyenv_configure_signature, '##pyenv:configure')
          task(:configure, :except => { :no_release => true }) {
            begin
              script_file = capture("mktemp /tmp/pyenv.XXXXXXXXXX").strip
              top.put(pyenv_configure_script, script_file)
              [ pyenv_configure_files ].flatten.each do |file|
                _update_config(script_file, file)
              end
            ensure
              run("rm -f #{script_file.dump}") rescue nil
            end
          }

          _cset(:pyenv_platform) { fetch(:platform_identifier) }
          _cset(:pyenv_python_dependencies) {
            case pyenv_platform.to_sym
            when :debian, :ubuntu
              %w(git-core build-essential libreadline6-dev zlib1g-dev libssl-dev libbz2-dev libsqlite3-dev)
            when :redhat, :fedora, :centos, :amazon, :amazonami
              %w(git-core autoconf gcc-c++ glibc-devel patch readline readline-devel zlib zlib-devel openssl openssl-devel bzip2 bzip2-devel sqlite sqlite-devel)
            else
              []
            end
          }
          task(:dependencies, :except => { :no_release => true }) {
            platform.packages.install(pyenv_python_dependencies)
          }

          _cset(:pyenv_python_versions) { pyenv.versions }
          desc("Build python within pyenv.")
          task(:build, :except => { :no_release => true }) {
#           reset!(:pyenv_python_versions)
            python = fetch(:pyenv_python_cmd, "python")
            if pyenv_use_virtualenv
              if pyenv_virtualenv_python_version != "system" and not pyenv_python_versions.include?(pyenv_virtualenv_python_version)
                pyenv.install(pyenv_virtualenv_python_version)
              end
              if pyenv_python_version != "system" and not pyenv_python_versions.include?(pyenv_python_version)
                pyenv.virtualenv(pyenv_virtualenv_python_version, pyenv_python_version)
              end
            else
              if pyenv_python_version != "system" and not pyenv_python_versions.include?(pyenv_python_version)
                pyenv.install(pyenv_python_version)
              end
            end
            pyenv.exec("#{python} --version") # chck if python is executable
          }

          # call `pyenv rehash` to update shims.
          def rehash(options={})
            invoke_command("#{pyenv_command} rehash", options)
          end

          def global(version, options={})
            invoke_command("#{pyenv_command} global #{version.dump}", options)
          end

          def invoke_command_with_path(cmdline, options={})
            path = options.delete(:path)
            if path
              chdir = "cd #{path.dump}"
              via = options.delete(:via)
              # as of Capistrano 2.14.2, `sudo()` cannot handle multiple command correctly.
              if via == :sudo
                invoke_command("#{chdir} && #{sudo} #{cmdline}", options)
              else
                invoke_command("#{chdir} && #{cmdline}", options.merge(:via => via))
              end
            else
              invoke_command(cmdline, options)
            end
          end

          def local(version, options={})
            invoke_command_with_path("#{pyenv_command} local #{version.dump}", options)
          end

          def which(command, options={})
            version = ( options.delete(:version) || pyenv_python_version )
            invoke_command_with_path("#{pyenv_command(:version => version)} which #{command.dump}", options)
          end

          def exec(command, options={})
            # users of pyenv.exec must sanitize their command line.
            version = ( options.delete(:version) || pyenv_python_version )
            invoke_command_with_path("#{pyenv_command(:version => version)} exec #{command}", options)
          end

          def versions(options={})
            capture("#{pyenv_command} versions --bare", options).split(/(?:\r?\n)+/)
          end

          def available_versions(options={})
            capture("#{pyenv_command} install --complete", options).split(/(?:\r?\n)+/)
          end

          _cset(:pyenv_install_python_threads) {
            capture("cat /proc/cpuinfo | cut -f1 | grep processor | wc -l").to_i rescue 1
          }
          # create build processes as many as processor count
          _cset(:pyenv_make_options) { "-j #{pyenv_install_python_threads}" }
          _cset(:pyenv_configure_options, nil)
          def install(version, options={})
            environment = {}
            environment["CONFIGURE_OPTS"] = pyenv_configure_options.to_s if pyenv_configure_options
            environment["MAKE_OPTS"] = pyenv_make_options.to_s if pyenv_make_options
            invoke_command("#{pyenv_command(:env => environment)} install #{version.dump}", options)
          end

          def uninstall(version, options={})
            invoke_command("#{pyenv_command} uninstall -f #{version.dump}", options)
          end

          def virtualenv(version, venv, options={})
            run("#{pyenv_cmd} virtualenv #{pyenv_virtualenv_options.join(" ")} #{version.dump} #{venv.dump}", options)
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
