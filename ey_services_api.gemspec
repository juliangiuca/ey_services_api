# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "ey_services_api/version"

Gem::Specification.new do |s|
  s.name        = "ey_services_api"
  s.version     = EY::ServicesAPI::VERSION
  s.authors     = ["Jacob & Thorben & David & mkb & Josh & Others"]
  s.email       = ["jacob@engineyard.com"]
  s.homepage    = "https://github.com/engineyard/ey_services_api"
  s.summary     = %q{API for Partner Services (talks to services.engineyard.com)}
  s.description = %q{API for Partner Services (talks to services.engineyard.com)}

  s.rubyforge_project = "ey_services_api"

  s.files         = (`git ls-files`.split("\n") - `git ls-files -- fake`.split("\n"))
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  
  s.add_development_dependency 'rspec'
  s.add_dependency 'json'
  s.add_dependency 'ey_api_hmac', ">= 0.3.0"
end
