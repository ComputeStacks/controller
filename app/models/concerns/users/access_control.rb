module Users
  module AccessControl
    extend ActiveSupport::Concern

    included do

      # Include default devise modules. Others available are:
      # :confirmable, :lockable, :timeoutable and :omniauthable
      devise :database_authenticatable, :registerable,
            :confirmable, :recoverable, :trackable,
            :validatable, :lockable, :timeoutable

      has_many :api_credentials, class_name: 'User::ApiCredential' #, dependent: :destroy  ## Using foreign key and cascade delete on the DB side.

      has_many :access_grants,
              class_name: 'Doorkeeper::AccessGrant',
              foreign_key: :resource_owner_id,
              dependent: :delete_all # or :destroy if you need callbacks

      has_many :access_tokens,
              class_name: 'Doorkeeper::AccessToken',
              foreign_key: :resource_owner_id,
              dependent: :delete_all # or :destroy if you need callbacks

      has_many :oauth_applications, class_name: 'Doorkeeper::Application', as: :owner

      before_destroy :clear_api_credentials!
      after_update :toggle_user_state
    end

    def suspend!
      update active: false
    end

    def unsuspend!
      update active: true
    end

    # def after_database_authentication
    #   Audit.create!(:user_id => self.id, :event => 'signin', :ip_addr => self.current_sign_in_ip)
    # end

    private

    def toggle_user_state
      if self.saved_change_to_attribute?("active")
        UserServices::ToggleActiveService.new(self, current_audit).perform
      end
    end

    def clear_api_credentials!
      api_credentials.each {|i| i.destroy}
    end

  end
end
