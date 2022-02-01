class ExceptionsController < ApplicationController

	def internal_server_error
		@sentry_event_id = SENTRY_CONFIGURED ? Raven.last_event_id : nil
		render layout: 'devise', status: 500
	end

end
