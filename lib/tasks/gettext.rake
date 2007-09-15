#
# Added for Ruby-GetText-Package
#

require 'noosfero'

desc "Create mo-files for L10n"
task :makemo do
  require 'gettext/utils'
  GetText.create_mofiles(true, "po", "locale")
end

desc "Update pot/po files to match new version."
task :updatepo do
  require 'gettext/utils'
  GetText.update_pofiles(Noosfero::PROJECT, Dir.glob("{app,lib}/**/*.{rb,rhtml}"),
                         "#{Noosfero::PROJECT} #{Noosfero::VERSION}")
end

# vim: ft=ruby
