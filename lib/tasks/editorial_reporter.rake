require 'travel_advice_reporter'

namespace :editorial_report do

  desc "Report on travel advice editorial changes exported as CSV"
  task :edition_changes => :environment do
    TravelAdviceReporter.edition_changes
  end

  desc "Report on broken links in travel advice pages exported as CSV"
  task :broken_links => :environment do
    TravelAdviceReporter.broken_links
  end
end
