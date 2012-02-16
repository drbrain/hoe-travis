require 'minitest/autorun'
require 'hoe/travis'
require 'tmpdir'

class TestHoeTravis < MiniTest::Unit::TestCase

  def setup
    @hoe = Hoe.spec "blah" do
      developer 'author', 'email@example'
      developer 'silent', ''

      self.readme_file = 'README.rdoc'
    end

    @hoe.extend Hoe::Travis

    @editor = ENV['EDITOR']
  end

  def teardown
    ENV['EDITOR'] = @editor
  end

  def test_have_gem_eh
    assert @hoe.have_gem? 'hoe'
    refute @hoe.have_gem? 'nonexistent'
  end

  def test_travis_before_script
    expected = @hoe.with_config do |config, _|
      config['travis']['before_script']
    end

    assert_equal expected, @hoe.travis_before_script
  end

  def test_travis_fake_config
    home = ENV['HOME']

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
  ensure
    ENV['HOME'] = home
  end

  def test_travis_notifications
    expected = {
      'email' => %w[email@example]
    }

    assert_equal expected, @hoe.travis_notifications
  end

  def test_travis_notifications_config
    Hoe::DEFAULT_CONFIG['travis']['notifications'] = {
      'email' => %w[other@example]
    }

    expected = {
      'email' => %w[other@example]
    }

    assert_equal expected, @hoe.travis_notifications
  ensure
    Hoe::DEFAULT_CONFIG['travis'].delete 'notifications'
  end

  def test_travis_versions
    def @hoe.have_gem?(name) false end

    assert_equal %w[1.8.7 1.9.2 1.9.3], @hoe.travis_versions
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
      io.write "travis"
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
        travis_yml = @hoe.travis_yml_generate

        expected = <<-TRAVIS_YML
---
before_script:
- gem install hoe-travis --no-rdoc --no-ri
- rake travis:before
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

