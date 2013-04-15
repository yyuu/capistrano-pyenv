v1.0.0 (Yamashita, Yuu)

* Rename some of options
  * `:pyenv_use_configure` -> `:pyenv_setup_shell`
  * `:pyenv_define_default_environment` -> `:pyenv_setup_default_environment`
* Add pyenv convenience methods such like `pyenv.global()` and `pyenv.exec()`.
* Add `:pyenv_make_options` and `:pyenv_configure_options` to control `python-build`. By default, create `make` jobs as much as processor count.

v1.0.1 (Yamashita, Yuu)

* Use [capistrano-platform-resources](https://github.com/yyuu/capistrano-platform-resources) to manage platform packages.
* Add `pyenv:setup_default_environment` task.
* Join `PATH` variables with ':' on generating `:default_environment` to respect pre-defined values.
* Fix a problem during invoking pyenv via sudo with path.

v1.0.2 (Yamashita, Yuu)

* Set up `:default_environment` after the loading of the recipes, not after the task start up.
* Fix a problem on generating `:default_environment`.

v1.0.3 (Yamashita, Yuu)

* Add support for extra flavors of RedHat.
* Remove useless gem dependencies.
