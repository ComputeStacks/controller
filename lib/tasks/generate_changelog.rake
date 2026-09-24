require "github/markup"

# Tag markers in CHANGELOG.md, and the badge each becomes in the rendered HTML.
CHANGELOG_TAGS = {
  "[FEATURE]" => "<span class='label label-success'>FEATURE</span>",
  "[FIX]" => "<span class='label label-danger'>FIX</span>",
  "[CHANGE]" => "<span class='label label-primary'>CHANGE</span>",
  "[DEPRECATED]" => "<span class='label label-warning'>DEPRECATED</span>"
}.freeze

# The topmost `## vX.Y.Z` heading, i.e. the release the notes currently describe.
# @return [String, nil]
def changelog_top_version(markdown)
  markdown[/^##\s+v?(\d+\.\d+\.\d+)\s*$/, 1]
end

# VERSION, minus the git sha the Dockerfile appends to it before this task runs
# (it rewrites the file as "<version>-<sha>" so the running app can report both).
# @return [String]
def released_version(raw)
  raw.strip.split("-").first.to_s
end

# Yields each run of HTML that is NOT inside a <pre> or <code> element, so a
# substitution cannot rewrite the inside of a fenced example.
def outside_code(html)
  html.split(%r{(<pre>.*?</pre>|<code>.*?</code>)}m).map { |chunk|
    chunk.start_with?("<pre>", "<code>") ? chunk : yield(chunk)
  }.join
end

namespace :version do
  ##
  # Fails if VERSION, the top CHANGELOG.md section, and the docker tag variables in
  # .gitlab-ci.yml disagree.
  #
  # These three drifted in the past: the comment on CS_MINOR_VERSION records that it
  # sat at 9.4 through the 9.5, 9.6 and 9.7 releases, so `:9.4` was the moving tag
  # for all three. Nothing checked, so nothing complained.
  #
  # It is fine for CHANGELOG.md to run AHEAD of VERSION while a release is being
  # written -- entries accumulate under the next version's heading. This is a
  # release-time check, which is why generate_changelog (an image-build step; the
  # `build` CI job never runs on a push) is what invokes it.
  desc "Verify VERSION, CHANGELOG.md and the docker tag variables agree"
  task check: :environment do
    version = released_version(File.read("#{Rails.root}/VERSION"))
    top = changelog_top_version(File.read("#{Rails.root}/CHANGELOG.md"))

    problems = []
    if top.nil?
      problems << "CHANGELOG.md has no `## vX.Y.Z` heading to compare against"
    elsif top != version
      problems << "VERSION is #{version} but CHANGELOG.md's newest section is v#{top}"
    end

    # .dockerignore excludes .gitlab-ci.yml, so it is NOT present in the image this
    # task runs inside -- only VERSION and CHANGELOG.md are. Check the tag variables
    # when the file is there (locally, and `just build`'s context) and say so when it
    # is not; the build job re-checks them in the shell, where both it and VERSION
    # exist. Skipping must never skip the comparison above.
    ci_path = Rails.root.join(".gitlab-ci.yml")
    tags = "not checked (.gitlab-ci.yml is not in this context)"
    if ci_path.exist?
      ci = ci_path.read
      ci_minor = ci[/^\s*CS_MINOR_VERSION:\s*"?([\d.]+)"?/, 1]
      ci_major = ci[/^\s*CS_MAJOR_VERSION:\s*"?(\d+)"?/, 1]
      expected_minor = version.split(".")[0..1].join(".")
      expected_major = version.split(".").first

      if ci_minor != expected_minor
        problems << "CS_MINOR_VERSION in .gitlab-ci.yml is #{ci_minor.inspect}, expected #{expected_minor.inspect} " \
                    "(the `:#{ci_minor}` docker tag would move instead of `:#{expected_minor}`)"
      end
      if ci_major != expected_major
        problems << "CS_MAJOR_VERSION in .gitlab-ci.yml is #{ci_major.inspect}, expected #{expected_major.inspect}"
      end
      tags = ":#{ci_major} :#{ci_minor}"
    end

    if problems.any?
      abort <<~MSG
        Release version mismatch:
        #{problems.map { |p| "  - #{p}" }.join("\n")}

        Bump VERSION to match the newest CHANGELOG.md section (and CS_MINOR_VERSION /
        CS_MAJOR_VERSION with it) before building a release image.
        Set SKIP_VERSION_CHECK=1 to build anyway.
      MSG
    end

    puts "version ok: #{version} (changelog v#{top}, tags #{tags})"
  end
end

##
# Renders CHANGELOG.md into the CHANGELOG.html that ships inside the container and
# is served at /admin/changelog. Presentation lives in app/assets/stylesheets/
# changelog.scss -- this task only produces semantic HTML plus the tag badges.
task generate_changelog: :environment do
  Rake::Task["version:check"].invoke unless ENV["SKIP_VERSION_CHECK"].present?

  markdown = File.read("#{Rails.root}/CHANGELOG.md")
  html = GitHub::Markup.render("CHANGELOG.md", markdown)

  # Drop the document title; the page renders its own "What's New" heading.
  html = html.sub(%r{<h1>.*?</h1>\s*}m, "")

  html = outside_code(html) do |chunk|
    CHANGELOG_TAGS.reduce(chunk) { |acc, (tag, badge)| acc.gsub(tag, badge) }
  end

  File.write("#{Rails.root}/CHANGELOG.html", html)
  puts "wrote CHANGELOG.html (#{html.bytesize} bytes)"
end
