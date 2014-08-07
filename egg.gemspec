Gem::Specification.new do |s|
  s.name        = 'egg'
  s.version     = '0.1.0'
  s.date        = '2014-08-07'
  s.summary     = "Egg"
  s.description = "Minimalist dependency management for XCode projects"
  s.authors     = ["Tabcorp"]
  s.email       = 'deema@tabcorp.com.au'
  s.files       = ["lib/egg.rb", "lib/egg/assertion.rb", "lib/egg/egg.rb", "lib/egg/eggfile.rb", "lib/egg/installedegg.rb", "lib/egg/installer.rb"]
  s.add_runtime_dependency 'xcodeproj', '~> 0.18.0'
  s.add_runtime_dependency 'git', '~> 1.2.8'
  s.executables << 'egg'
end
