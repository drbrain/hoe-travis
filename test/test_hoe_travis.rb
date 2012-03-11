require 'minitest/autorun'
require 'hoe/travis'
require 'tmpdir'
require 'fileutils'

class TestHoeTravis < MiniTest::Unit::TestCase

  def setup
    Rake.application.clear

    @hoe = Hoe.spec "blah" do
      developer 'author', 'email@example'
      developer 'silent', ''

      self.readme_file = 'README.rdoc'
    end

    @hoe.extend Hoe::Travis

    @editor = ENV['EDITOR']
    @home   = ENV['HOME']
  end

  def teardown
    ENV['EDITOR'] = @editor
    ENV['HOME']   = @home
  end

  def test_define_travis_tasks
    @hoe.define_travis_tasks

    travis = Rake::Task['travis']
    assert_equal %w[test], travis.prerequisites

    after       = Rake::Task['travis:after']
    assert_equal %w[travis:fake_config check_manifest], after.prerequisites

    before      = Rake::Task['travis:before']
    assert_equal %w[install_plugins check_extra_deps], before.prerequisites

    check       = Rake::Task['travis:check']
    assert_empty check.prerequisites

    disable     = Rake::Task['travis:disable']
    assert_empty disable.prerequisites

    edit        = Rake::Task['travis:edit']
    assert_empty edit.prerequisites

    enable      = Rake::Task['travis:enable']
    assert_empty enable.prerequisites

    force       = Rake::Task['travis:force']
    assert_empty force.prerequisites

    fake_config = Rake::Task['travis:fake_config']
    assert_empty fake_config.prerequisites

    generate    = Rake::Task['travis:generate']
    assert_empty generate.prerequisites
  end

  def test_travis_after_script
    expected = [
      'rake travis:after -t',
    ]

    assert_equal expected, @hoe.travis_after_script
  end

  def test_travis_before_script
    expected = [
      'gem install hoe-travis --no-rdoc --no-ri',
      'rake travis:before -t',
    ]

    assert_equal expected, @hoe.travis_before_script
  end

  def test_travis_fake_config
    Dir.mktmpdir do |path|
      ENV['HOME'] = path

      fake_config = File.expand_path '~/.hoerc'

      @hoe.travis_fake_config

      assert File.exist? fake_config

      expected = {
        'exclude' => /\.(git|travis)/
      }

      assert_equal expected, YAML.load_file(fake_config)
    end
  end

  def test_travis_notifications
    expected = {
      'email' => %w[email@example]
    }

    assert_equal expected, @hoe.travis_notifications
  end

  def test_travis_notifications_config
    Hoe::DEFAULT_CONFIG['travis']['notifications'] = {
      'email' => %w[other@example],
      'irc' => %w[irc.example#channel],
    }

    expected = {
      'email' => %w[other@example],
      'irc'   => %w[irc.example#channel],
    }

    Dir.mktmpdir do |dir|
      ENV['HOME'] = dir
      assert_equal expected, @hoe.travis_notifications
    end
  ensure
    Hoe::DEFAULT_CONFIG['travis'].delete 'notifications'
  end

  def test_travis_script
    expected = 'rake travis'


    assert_equal expected, @hoe.travis_script
  end

  def test_travis_versions
    def @hoe.have_gem?(name) false end

    assert_equal %w[1.8.7 1.9.2 1.9.3], @hoe.travis_versions
  end

  def test_travis_versions_multiruby
    def @hoe.have_gem?(name) true end
    def @hoe.`(command) "Passed: 1.6.8, 1.8.0" end

    Dir.mktmpdir do |path|
      ENV['HOME'] = path

      FileUtils.touch File.join(path, '.multiruby')

      assert_equal %w[1.6.8 1.8.0], @hoe.travis_versions
    end
  end

  def test_travis_versions_multiruby_unused
    def @hoe.have_gem?(name) true end

    Dir.mktmpdir do |path|
      ENV['HOME'] = path

      assert_equal %w[1.8.7 1.9.2 1.9.3], @hoe.travis_versions
    end
  end

  def test_travis_yml_check
    Tempfile.open 'travis' do |io|
      io.write "---\nlanguage: ruby\nrvm:\n  - 1.8.7\n"
      io.rewind

      assert @hoe.travis_yml_check io.path
    end
  end

  def test_travis_yml_check_invalid
    Tempfile.open 'travis' do |io|
      io.write "---\nlanguage: ruby\n"
      io.rewind

      out, err = capture_io do
        refute @hoe.travis_yml_check io.path
      end

      assert_empty out
      refute_empty err
    end
  end

  def test_travis_yml_edit
    Tempfile.open 'out' do |out_io|
      ENV['EDITOR'] = "cat > #{out_io.path} < "

      Tempfile.open 'travis' do |io|
        io.write "---\nlanguage: ruby\nrvm:\n  - 1.8.7\n"
        io.rewind

        @hoe.travis_yml_edit io.path
      end

      assert_equal "---\nlanguage: ruby\nrvm:\n  - 1.8.7\n", out_io.read
    end
  end

  def test_travis_yml_edit_bad
    ENV['EDITOR'] = "cat > /dev/null < "

    Tempfile.open 'travis' do |io|
      io.write "travis: woo"
      io.rewind

      e = assert_raises SystemExit do
        capture_io do
          @hoe.travis_yml_edit io.path
        end
      end

      assert_equal 1, e.status
    end
  end

  def test_travis_yml_generate
    def @hoe.have_gem?(name) false end

    Dir.mktmpdir do |path|
      Dir.chdir path do
        travis_yml = YAML.load @hoe.travis_yml_generate

        expected = YAML.load <<-TRAVIS_YML
---
after_script:
- rake travis:after -t
before_script:
- gem install hoe-travis --no-rdoc --no-ri
- rake travis:before -t
language: ruby
notifications:
  email:
  - email@example
rvm:
- 1.8.7
- 1.9.2
- 1.9.3
script: rake travis
        TRAVIS_YML

        assert_equal expected, travis_yml
      end
    end
  end

  def test_travis_yml_write
    Dir.mktmpdir do |path|
      Dir.chdir path do
        open 'travis', 'w' do |io| io.write 'travis' end

        @hoe.travis_yml_write 'travis'

        assert File.exist? '.travis.yml'

        assert_equal 'travis', File.read('.travis.yml')
      end
    end
  end

end

