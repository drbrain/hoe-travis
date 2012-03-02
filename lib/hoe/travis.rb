require 'hoe'
require 'tempfile'
require 'net/http'
require 'net/https' # for Ruby 1.8
require 'uri'

##
# The travis plugin for Hoe manages your .travis.yml file for you in a clean
# and extensible way you can use across projects or by through integration
# with other Hoe plugins.
#
# == Setup
#
# The travis plugin can be used without this setup.  By following these
# instructions you can enable and disable a travis-ci hook for your ruby
# projects from rake through <code>rake travis:enable</code> and <code>rake
# travis:disable</code>.
#
# === Github API access
#
# Set your github username and password in your ~/.gitconfig:
#
#   git config --global github.user username
#   git config --global github.password password
#   chmod 600 ~/.gitconfig
#
# === Travis token
#
# As of this writing there isn't an easy way to retrieve the travis token
# programmatically.  You can find your travis token at
# http://travis-ci.org/profile underneath your github username and email
# address.
#
# To set this in your hoerc run <code>rake config_hoe</code> and edit the
# "token:" entry.
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
# travis:enable::
#   Enables the travis hook on github.com.  Requires further setup as
#   described below.
#
# travis:disable::
#   Disables the travis hook on github.com.  Requires further setup as
#   described below.
#
# travis:force::
#   Forces a travis-ci run, equivalent to clicking the "test" button on the
#   travis-ci hook page.
#
# == Hoe Configuration
#
# The Hoe configuration is used to generate the .travis.yml.  After you've
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
# token::
#   Your travis-ci token.  See @Setup above
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

  YAML_EXCEPTIONS = if defined?(Psych) then # :nodoc:
                      if Psych.const_defined? :Exception then
                        [Psych::SyntaxError] # Ruby 1.9.2
                      else
                        [Psych::Exception, Psych::SyntaxError]
                      end
                    else
                      [YAML::Error]
                    end

  YAML_EXCEPTIONS << ArgumentError

  Hoe::DEFAULT_CONFIG['travis'] = {
    'before_script' => [
      'gem install hoe-travis --no-rdoc --no-ri',
      'rake travis:before',
    ],
    'script' => 'rake travis',
    'token' => 'FIX - See: ri Hoe::Travis',
    'versions' => %w[
      1.8.7
      1.9.2
      1.9.3
    ],
  }

  def initialize_travis # :nodoc:
    @github_api = URI 'https://api.github.com'
  end

  ##
  # Adds travis tasks to rake

  def define_travis_tasks
    desc "Runs your tests for travis"
    task :travis => %w[test travis:fake_config check_manifest]

    namespace :travis do
      desc "Run by travis-ci before your running the default checks"
      task :before => %w[
        check_extra_deps
        install_plugins
      ]

      desc "Runs travis-lint on your .travis.yml"
      task :check do
        abort unless check_travis_yml '.travis.yml'
      end

      desc "Disables the travis-ci hook"
      task :disable do
        travis_disable
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

      desc "Enables the travis-ci hook"
      task :enable do
        travis_enable
      end

      desc "Triggers the travis-ci hook"
      task :force do
        travis_force
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

  ##
  # Extracts the travis before_script from your .hoerc

  def travis_before_script
    with_config { |config, _|
      config['travis']['before_script'] or
        Hoe::DEFAULT_CONFIG['travis']['before_script']
    }
  end

  ##
  # Disables travis-ci for this repository.

  def travis_disable
    _, repo, = travis_github_check

    if hook = travis_have_hook?(repo) then
      travis_edit_hook repo, hook, false if hook['active']
    end
  end

  ##
  # Edits the travis +hook+ definition for +repo+ (from the github URL) to
  # +enable+ (default) or disable it.

  def travis_edit_hook repo, hook, enable = true
    patch = unless Net::HTTP.const_defined? :Patch then
              # Ruby 1.8
              Class.new Net::HTTPRequest do |c|
                c.const_set :METHOD, 'PATCH'
                c.const_set :REQUEST_HAS_BODY, true
                c.const_set :RESPONSE_HAS_BODY, true
              end
            else
              Net::HTTP::Patch
            end


    id = hook['id']

    body = {
      'name'   => hook['name'],
      'active' => enable,
      'config' => hook['config']
    }

    travis_github_request "/repos/#{repo}/hooks/#{id}", body, patch
  end

  ##
  # Enables travis-ci for this repository.

  def travis_enable
    user, repo, token = travis_github_check

    if hook = travis_have_hook?(repo) then
      travis_edit_hook repo, hook unless hook['active']
    else
      travis_make_hook repo, user, token
    end
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
  # Forces the travis-ci hook

  def travis_force
    user, repo, token = travis_github_check

    unless hook = travis_have_hook?(repo)
      hook = travis_make_hook repo, user, token
    end

    travis_github_request "/repos/#{repo}/hooks/#{hook['id']}/test", {}
  end

  ##
  # Ensures you have proper setup for editing the github travis hook

  def travis_github_check
    user = `git config github.user`.chomp
    abort <<-ABORT unless user
Set your github user and token in ~/.gitconfig

See: ri Hoe::Travis and
\thttp://help.github.com/set-your-user-name-email-and-github-token/
    ABORT

    `git config remote.origin.url` =~ /^git@github\.com:(.*).git$/
    repo = $1

    abort <<-ABORT unless repo
Unable to determine your github repository.

Expected \"git@github.com:[repo].git\" as your remote origin
    ABORT

    token = with_config do |config, _|
      config['travis']['token']
    end

    abort 'Please set your travis token via `rake config_hoe` - ' \
          'See: ri Hoe::Travis' if token =~ /FIX/

    return user, repo, token
  end

  ##
  # Makes a github request at +path+ with an optional +body+ Hash which will
  # be sent as JSON.  The default +method+ without a body is a GET request,
  # otherwise POST.

  def travis_github_request(path, body = nil,
                            method = body ? Net::HTTP::Post : Net::HTTP::Get)
    begin
      require 'json'
    rescue LoadError => e
      raise unless e.message.end_with? 'json'

      abort 'Please gem install json like modern ruby versions have'
    end

    uri = @github_api + path

    http = Net::HTTP.new uri.host, uri.port
    http.use_ssl = uri.scheme.downcase == 'https'
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.cert_store = OpenSSL::X509::Store.new
    http.cert_store.set_default_paths

    req = method.new uri.request_uri
    if body then
      req.content_type = 'application/json'
      req.body = JSON.dump body
    end

    user = `git config github.user`.chomp
    pass = `git config github.password`.chomp
    req.basic_auth user, pass

    res = http.request req

    body = JSON.parse res.body if res.class.body_permitted?

    unless Net::HTTPSuccess === res then
      message = ": #{res['message']}" if body

      raise "github API error #{res.code}#{message}"
    end

    body
  end

  ##
  # Returns the github hook definition for the "travis" hook on +repo+ (from
  # the github URL), if it exists.

  def travis_have_hook? repo
    body = travis_github_request "/repos/#{repo}/hooks"

    body.find { |hook| hook['name'] == 'travis' }
  end

  ##
  # Creates a travis hook for +user+ on the given +repo+ (from the github URL)
  # that uses the users +token+.

  def travis_make_hook repo, user, token
    body = {
      "name" => "travis",
      "active" => true,
      "config" => {
        "domain" => "",
        "token" => token,
        "user" => user,
      }
    }

    travis_github_request "/repos/#{repo}/hooks", body
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
      config['travis']['notifications'] or
        Hoe::DEFAULT_CONFIG['travis']['notifications']
    end || {}

    default_notifications.merge notifications
  end

  ##
  # Extracts the travis script from your .hoerc

  def travis_script
    with_config { |config, _|
      config['travis']['script'] or
        Hoe::DEFAULT_CONFIG['travis']['script']
    }
  end

  ##
  # Determines the travis versions from multiruby, if available, or your
  # .hoerc.

  def travis_versions
    if have_gem? 'ZenTest' and
       File.exist?(File.expand_path('~/.multiruby')) then
      `multiruby -v` =~ /^Passed: (.*)/

        $1.split(', ').map do |ruby_release|
        ruby_release.sub(/-.*/, '')
      end
    else
      with_config do |config, _|
        config['travis']['versions'] or
          Hoe::DEFAULT_CONFIG['travis']['versions']
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
  rescue *YAML_EXCEPTIONS => e
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
      'script'        => travis_script,
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

