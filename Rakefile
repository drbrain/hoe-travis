# -*- ruby -*-

# Bootstrap for travis-ci
$LOAD_PATH.unshift 'lib'

require 'rubygems'
require 'hoe'

Hoe.plugin :minitest
Hoe.plugin :git
Hoe.plugin :travis

Hoe.spec 'hoe-travis' do
  developer 'Eric Hodel', 'drbrain@segment7.net'

  rdoc_locations << 'docs.seattlerb.org:/data/www/docs.seattlerb.org/hoe-travis/'

  # this explicit dependency is so `gem install hoe-travis` will fetch
  # hoe and rake, simplifying the before_script command list
  self.extra_deps << ['hoe', '~> 3.0']
end

# vim: syntax=ruby
