require 'csv'
require 'diffy'
require 'resolv-replace'

class TravelAdviceReporter

  def self.edition_changes
    CSV.open("#{Rails.root}/../travel-advice-changes-#{Time.now.strftime("%y-%m-%d.%H-%M-%S")}.csv", "wb") do |csv|
      csv << ["Country", "Version", "Updated", "Updated by", "Lines removed", "Lines added", "Url", "Change description"]

      country_slugs.each do |country_slug|
        previous_edition = nil

        TravelAdviceEdition.where(country_slug: country_slug)
          .any_in(state: ['published', 'archived'])
          .order_by(:version_number).each do |e|

            editions_data = []
            editions_data << version_data(e, previous_edition)
            csv << editions_data.flatten
            previous_edition = e
        end
      end
    end
  end

  def self.broken_links
    markdown_links_re = /\[(.*?)\]\((.*?)\)/
    CSV.open("#{Rails.root}/../travel-advice-broken-links-#{Time.now.strftime("%y-%m-%d.%H-%M-%S")}.csv", "wb") do |csv|
      csv << ["Source", "Link text", "URL"]
      country_slugs.each do |country_slug|
        TravelAdviceEdition.where(country_slug: country_slug, state: 'published').each do |e|
          links_matches = { 'summary' => e.summary.scan(markdown_links_re) }
          e.parts.each do |part|
            links_matches[part.slug] = part.body.scan(markdown_links_re)
          end
          links_matches.each do |section, links|
            links.each do |link|
              link_text = link.first
              url = link.second
              next if url =~ /^mailto/

              url = url.split(" ").first
              url = URI.decode(url)
              unless url =~ /^http/
                url = "https://www.gov.uk#{url}"
              end

              puts "Attempting to connect to #{url}"

              begin
                uri = URI(url)
                http = Net::HTTP.new(uri.host, uri.port)
                http.use_ssl = (uri.scheme == "https")
                req = Net::HTTP::Get.new(uri.request_uri)
                res = http.request(req)
                unless res.is_a?(Net::HTTPSuccess) or res.is_a?(Net::HTTPRedirection)
                  csv << [ta_url(country_slug, section), link_text, url]
                end
              rescue
                puts "Error: #{res.class}"
                csv << [ta_url(country_slug, section), link_text, url]
              end
            end if links
          end if links_matches
        end
      end
    end
  end

  private

  def self.ta_url(country_slug, part_slug)
    url = "https://www.gov.uk/foreign-travel-advice/#{country_slug}"
    url = "#{url}/#{part_slug}" unless part_slug == 'summary'
    url
  end

  def self.country_slugs
    TravelAdviceEdition.all.distinct(:country_slug)
  end

  def self.version_data(current, previous)
    data = [current.country_slug, current.version_number, current.updated_at, publishing_user(current)]

    unless previous.nil?
      previous_content = summary_and_whole_body(previous)
      current_content = summary_and_whole_body(current)
      if previous_content != current_content
        diff = Diffy::Diff.new(current_content, previous_content, include_diff_info: true).to_s
        changes = subtractions_and_additions(diff)
      end
    end
    changes ||= ["No changes", "No changes"]

    data << changes

    data << edition_url(current)
    data << current.change_description
    data.flatten
  end

  def self.subtractions_and_additions(diff)
    diff_info = diff.split("\n")[2] # The diff header info.
    matchdata = /^@@ \-\d+,(\d+) \+\d+,(\d+) @@$/.match(diff_info)
    [matchdata[1], matchdata[2]]
  end

  def self.edition_url(edition)
    "https://travel-advice-publisher.preview.alphagov.co.uk/admin/editions/#{edition.to_param}/edit"
  end

  def self.publishing_user(edition)
    publish_action = edition.actions.to_a.find { |a| a.request_type == "publish" }
    publish_action.requester.name if publish_action
  end

  def self.summary_and_whole_body(edition)
    "#{edition.summary}\n\n#{edition.whole_body}"
  end
end
