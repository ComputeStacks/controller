require "test_helper"

##
# Every locale the app ships must resolve the clone strings.
#
# There is no i18n-tasks CI job, and a missing key in a non-default locale renders as
# "translation missing: fr.volumes…" straight into the customer's page — silently, because
# nothing in dev exercises the non-English locales.
class VolumeCloneLocaleTest < ActiveSupport::TestCase
  include CloneTestHelpers

  LOCALES = %i[en de fi fr nl].freeze

  test "every locale resolves the umbrella event message" do
    LOCALES.each do |locale|
      value = I18n.t "events.messages.#{CLONE_LOCALE}", volume: "webroot", locale: locale, default: nil
      refute_nil value, "#{locale} is missing events.messages.#{CLONE_LOCALE}"
      assert_includes value, "webroot", "#{locale} drops the volume interpolation"
    end
  end

  test "every locale resolves every clone status string" do
    leaves = %w[column restoring failed banner_help banner_failed_help details]

    LOCALES.each do |locale|
      leaves.each do |leaf|
        refute_nil I18n.t("volumes.clone_status.#{leaf}", locale: locale, default: nil),
          "#{locale} is missing volumes.clone_status.#{leaf}"
      end

      [1, 2].each do |count|
        %w[banner banner_failed].each do |key|
          value = I18n.t "volumes.clone_status.#{key}", count: count, locale: locale, default: nil
          refute_nil value, "#{locale} is missing volumes.clone_status.#{key} for count=#{count}"
          refute_includes value.to_s, "%{count}", "#{locale}.#{key} left %{count} uninterpolated"
        end
      end
    end
  end

  # Every state the machine can sit in has to have something to say, or a customer watching a
  # 40-minute clone sees a blank line where the progress should be.
  test "every working state has a step label in every locale" do
    LOCALES.each do |locale|
      VolumeCloneJob::WORKING_STATES.each do |state|
        refute_nil I18n.t("volumes.clone_status.steps.#{state}", locale: locale, default: nil),
          "#{locale} is missing volumes.clone_status.steps.#{state}"
      end
    end
  end
end
