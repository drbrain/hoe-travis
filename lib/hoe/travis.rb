require 'hoe'
require 'tempfile'

##
# The travis plugin for Hoe manages your .travis.yml file for you in a clean
# and extensible way you can use across projects or by through integration
# with other Hoe plugins.
#
# == Tasks
#
# You can extend the following tasks in your Rakefile or Hoe plugins to add
# extra checks to travis-ci.
#
# travis::
#   Run by travis-ci.  Defaults to running your tests and checking your
#   manifest file.  You can run this locally to check what travis-ci will do.
#
# travis:before::
#   Runs as the before_script on travis-ci.  Defaults to installing your
#   development dependencies.
#
# travis:check::
#   Runs travis-lint against your .travis.yml.
#
# travis:edit::
#   Pulls up your .travis.yml in your EDITOR and runs travis-lint upon saving.
#   Does not allow you to save a bad .travis.yml.
#
# travis:generate::
#   Generates a .travis.yml based on your Hoe spec and .hoerc then brings it
#   up in your EDITOR and runs travis-lint upon saving.  Does not allow you to
#   save a bad .travis.yml.
#
# == Config
#
# The configuration is only used to generate the .travis.yml.  After you've
# generated a .travis.yml you may any changes you wish to it and the following
# defaults will not apply.  If you have multiple projects, setting up a common
# custom configuration in ~/.hoerc can save you time.
#
# The following default configuration options are provided under the "travis"
# key of the Hoe configuration (accessible from Hoe#with_config):
#
# before_script::
#   Array of commands run before the test script.  Defaults to installing
#   hoe-travis and its dependencies (rake and hoe) followed by running the
#   travis:before rake task.
#
# script::
#   Runs the travis rake task.
#
# versions::
#   The versions of ruby used to run your tests.  Note that if you have
#   multiruby installed, your installed versions will be preferred over the
#   defaults of ruby 1.8.7, 1.9.2 and 1.9.3.
#
# In your .hoerc you may provide a "notifications" key such as:
#
#   travis:
#     notifications:
#       irc: "irc.example#your_channel"
#
# Notifications specified in a .hoerc will override the default email
# notifications created from the Hoe spec.

module Hoe::Travis

  ##
  # This version of Hoe::Travis

  VERSION = '1.0'

  Hoe::DEFAULT_CONFIG['travis'] = {
    'before_script' => [
      'gem install hoe-travis --no-rdoc --no-ri',
      'rake travis:before',
    ],
    'script' => 'rake travis',
    'versions' => %w[
      1.8.7
      1.9.2
      1.9.3
    ],
  }

  ##
  # Adds travis tasks to rake

  def define_travis_tasks
    desc "Runs your tests for travis"
    task :travis => %w[test travis:fake_config check_manifest]

    namespace :travis do
      desc "Run by travis-ci before your running the default checks"
      task :before => %w[
        check_extra_deps
      ]

      desc "Runs travis-lint on your .travis.yml"
      task :check do
        abort unless check_travis_yml '.travis.yml'
      end

      desc "Brings .travis.yml up in your EDITOR then checks it on save"
      task :edit do
        Tempfile.open 'travis.yml' do |io|
          io.write File.read '.travis.yml'
          io.rewind

          ok = travis_yml_edit io.path

          travis_yml_write io.path if ok
        end
      end

      task :fake_config do
        travis_fake_config
      end

      desc "Generates a new .travis.yml and allows you to customize it with your EDITOR"
      task :generate do
        Tempfile.open 'travis.yml' do |io|
          io.write travis_yml_generate
          io.rewind

          ok = travis_yml_edit io.path

          travis_yml_write io.path if ok
        end
      end
    end
  end

  def have_gem? name # :nodoc:
    Gem::Specification.find_by_name name
  rescue Gem::LoadError
    return false
  end

  ##
  # Extracts the travis before_script from your .hoerc

  def travis_before_script
    with_config { |config, _| config['travis']['before_script'] }
  end

  ##
  # Creates a fake config file for use on travis-ci.  Running this with a
  # pre-existing .hoerc has no effect.

  def travis_fake_config
    fake_hoerc = File.expand_path '~/.hoerc'

    return if File.exist? fake_hoerc

    config = { 'exclude' => /\.(git|travis)/ }

    open fake_hoerc, 'w' do |io|
      YAML.dump config, io
    end
  end

  ##
  # Creates the travis notifications hash from the developers for your
  # project.  The developer will be merged with the travis notifications from
  # your .hoerc.

  def travis_notifications
    email = @email.compact
    email.delete ''

    default_notifications = { 'email' => email }
    notifications = with_config do |config, _|
      config['travis']['notifications']
    end || {}

    default_notifications.merge notifications
  end

  ##
  # Determines the travis versions from multiruby, if available, or your
  # .hoerc.

  def travis_versions
    if have_gem? 'ZenTest' then
      `multiruby -v` =~ /^Passed: (.*)/

        $1.split(', ').map do |ruby_release|
        ruby_release.sub(/-.*/, '')
      end
    else
      with_config do |config, _|
        config['travis']['versions']
      end
    end.sort
  end

  ##
  # Runs travis-lint against the travis.yml in +path+.  If the file is OK true
  # is returned, otherwise the issues are displayed on $stderr and false is
  # returned.

  def travis_yml_check path
    require 'travis/lint'

    travis_yml = YAML.load_file path

    issues = Travis::Lint::Linter.validate travis_yml

    return true if issues.empty?

    issues.each do |issue|
      warn "There is an issue with the key #{issue[:key].inspect}:"
      warn "\t#{issue[:issue]}"
    end

    false
  rescue ArgumentError, Psych::SyntaxError => e
    warn "invalid YAML in travis.yml file at #{path}: #{e.message}"

    return false
  end

  ##
  # Loads the travis.yml in +path+ in your EDITOR (or vi if unset).  Upon
  # saving the travis.yml is checked with travis-lint.  If any problems are
  # found you will be asked to retry the edit.
  #
  # If the edited travis.yml is OK true is returned, otherwise false.

  def travis_yml_edit path
    loop do
      editor = ENV['EDITOR'] || 'vi'

      system "#{editor} #{path}"

      break true if travis_yml_check path

      abort unless $stdout.tty?

      print "\nRetry edit? [Yn]\n> "
      $stdout.flush

      break false if $stdin.gets =~ /\An/i
    end
  end

  ##
  # Generates a travis.yml from .hoerc, the Hoe spec and the default
  # configuration.

  def travis_yml_generate
    travis_yml = {
      'before_script' => travis_before_script,
      'language'      => 'ruby',
      'notifications' => travis_notifications,
      'rvm'           => travis_versions,
      'script'        => 'rake travis'
    }

    travis_yml.each do |key, value|
      travis_yml.delete key unless value
    end

    YAML.dump travis_yml
  end

  ##
  # Writes the travis.yml in +source_file+ to .travis.yml in the current
  # directory.  Overwrites an existing .travis.yml.

  def travis_yml_write source_file
    open source_file do |source_io|
      open '.travis.yml', 'w' do |dest_io|
        dest_io.write source_io.read
      end
    end
  end

end

