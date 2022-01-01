require 'github/markup'
task generate_changelog: :environment do

  raw_html = GitHub::Markup.render('CHANGELOG.md', File.read('CHANGELOG.md'))

  raw_html = raw_html.gsub("<ul>", %q(<ul class="list-unstyled">))
  raw_html = raw_html.gsub("<h1>", %q(<div style="display:none;">)).gsub("</h1>", "</div>")
  raw_html = raw_html.gsub("h2", "h4")
  raw_html = raw_html.gsub("<h3>", %q(<div style="margin-top:-3px;margin-bottom:20px;text-transform:uppercase;"><small><b>)).gsub("</h3>", "</b></small></div>")
  raw_html = raw_html.gsub("[FEATURE]", "<span class='label label-success'>FEATURE</span>")
  raw_html = raw_html.gsub("[FIX]", "<span class='label label-danger'>FIX</span>")
  raw_html = raw_html.gsub("[CHANGE]", "<span class='label label-primary'>CHANGE</span>")
  raw_html = raw_html.gsub("[DEPRECATED]", "<span class='label label-warning'>DEPRECATED</span>")
  raw_html = raw_html.gsub("<p>","").gsub("</p>","")

  File.open("#{Rails.root.to_s}/CHANGELOG.html", 'w') do |f|
    f << raw_html
  end

end