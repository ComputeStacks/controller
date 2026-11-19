class Api::System::AlertNotificationsController < Api::System::BaseController
  protect_from_forgery except: :create

  def create
    StoreAlertService.new(alert_params).perform
    head :ok
  end

  private

  def alert_params
    params.permit(
      :receiver, :status, alerts: [[
        :fingerprint,
        :status,
        labels: {},
        annotations: [
          :description,
          :summary
        ]
      ]]
    )
  end
end
