require 'git'

require 'egg/eggfile'
require 'egg/installedegg'
require 'egg/gitReferenceLibrary'

##############################################
# Class to represent an egg that has been installed
# NB: dependencies may not have been installed yet, and it may need to be updated to a different commit
class InstalledEgg
  attr_reader :name, :remote, :installationRootPath, :installationPath, :relativePath, :sha

    def initialize(name, remote, relativePath, installationRootPath, installationPath)
        @name = name
        @remote = remote
        @relativePath = relativePath
        @installationRootPath = installationRootPath
        @installationPath = installationPath
        @sha = nil
        loadEggfile
    end

    def ensureCompatibilityWith(remote)
      if @relativePath
        return
      end

      repo = Git.open(installationPath)
      origin = repo.remote('origin')
      if !origin || remote != origin.url
        raise "[!] #{name} already on disk, but does not match source repo #{remote}; aborting!"
      end
    end

    # Installs an egg, (not its dependencies)
    # This is done by either cloning the repo, or updating the repo if it already exists
    def self.installEgg(egg, path)
      installationPath = "#{path}/#{egg.name}"
      name = egg.name
      sha = egg.sha

      if egg.relativePath
          # Create symlink
          FileUtils.symlink File.absolute_path(egg.relativePath), installationPath unless File.exists? installationPath
          return InstalledEgg.new(name, nil, egg.relativePath, path, installationPath)
      else
          remote = egg.url

          if File.exists? installationPath
            repo = Git.open(installationPath)
            origin = repo.remote('origin')
            if !origin || remote != origin.url
              raise "[!] #{name} already on disk, but does not match source repo #{remote}; aborting!"
            end
            GitReferenceLibrary.instance.update(remote)
            puts "Updating #{name}"
            repo.checkout('master')
            repo.pull
          else
            GitReferenceLibrary.instance.clone(remote, installationPath)
          end

          installedEgg = InstalledEgg.new(name, remote, nil, path, installationPath)
          if sha
            installedEgg.sha = sha
          end

          return installedEgg
      end
    end

    def sha=(value)
      if sha == value
        return
      end

      raise "#{@name} already locked to commit #{@sha}" unless !@sha
      raise "#{@name} is locked to path #{@relativePath}, cannot specify sha" unless !@relativePath
      @sha = value

      puts "Updating #{name} to commit #{@sha}"
      repo = Git.open(@installationPath)
      origin = repo.remote('origin')
      origin.fetch
      repo.checkout(@sha)

      loadEggfile
    end

    def dependencies
      if @eggfile
        return @eggfile.eggs
      else
        return []
      end
    end

    private
    def loadEggfile
      @eggfile = nil
      eggfilePath = "#{@installationPath}/#{@name}.eggfile"
      if File.exists? eggfilePath
        @eggfile = Eggfile.read(eggfilePath)

        doteggs = "#{@installationPath}/.eggs"
        Dir.mkdir doteggs unless File.exists? doteggs

        relativeLinkPath = "../.."
        rootEggPath = Pathname.new(@installationRootPath)
        if @relativePath
          symlinkPath = Pathname.new(File.join(@relativePath,".eggs"))
          relativeLinkPath = rootEggPath.relative_path_from(symlinkPath)
        end
        linkpath = "#{doteggs}/#{@name}"
        FileUtils.symlink relativeLinkPath, linkpath unless File.exists? linkpath
        linkpath = "#{doteggs}/#{rootEggPath.basename}"
        FileUtils.symlink relativeLinkPath, linkpath unless File.exists? linkpath
      end
    end
end
