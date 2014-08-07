require 'egg/assertion'

##############################################
# Class to represent an Egg
class Egg
  attr_reader :name, :url, :relativePath, :sha

    def initialize(name, config)
        @name = name
        @config = config

        @relativePath = config[:path]
        @url = config[:url]
        @sha = config[:sha]

        assert {url || relativePath}
    end
end
