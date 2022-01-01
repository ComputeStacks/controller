module Admin::BillingPhasesHelper

  def selectable_phases(resource, current_phase = nil)
    master_phases = [
        ['Trial', 'trial'],
        ['Discount', 'discount'],
        ['Final', 'final']
    ]
    current_phases = resource.available_phases.map {|i| i.phase_type}
    phases = []
    master_phases.each do |label, value|
      if current_phase
        phases << [label, value] if !current_phases.include?(value) || current_phase == value
      else
        phases << [label, value] unless current_phases.include?(value)
      end
    end
    phases
  end

  def phase_durations
    [
        ['Hours', 'hours'],
        ['Days', 'days'],
        ['Months', 'months'],
        ['Years', 'years']
    ]
  end

  def price_terms
    [
        [I18n.t("billing.hour"), 'hour'],
        [I18n.t("billing.month"), 'month'],
        [I18n.t("billing.year"), 'year']
    ]
  end

end
