##
# Sftp Host Key
#
# Generates and stores host keys to avoid key mismatch errors
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute sftp_container
#   @return [Deployment::Sftp]
#
# @!attribute algo
#   @return [rsa,ed25519]
#
# @!attribute [r] pubkey
#   @return [String]
#
# @!attribute [r] pkey
#   @return [String]
#
class Deployment::SftpHostKey < ApplicationRecord

  scope :rsa, -> { where algo: 'rsa' }
  scope :ed25519, -> { where algo: 'ed25519' }

  belongs_to :sftp_container, class_name: 'Deployment::Sftp', foreign_key: 'sftp_container_id'

  validates :algo, inclusion: { in: %w(ed25519 rsa) }
  before_create :generate_certificate

  private

  def generate_certificate
    filename = "/tmp/#{SecureRandom.alphanumeric(10)}"
    if algo == 'ed25519'
      `ssh-keygen -t ed25519 -f #{filename} -q -C "#{sftp_container.name}"`
    else
      `ssh-keygen -b 2048 -t rsa -f #{filename} -q -C "#{sftp_container.name}"`
    end
    self.pkey = File.read(filename)
    self.pubkey = File.read("#{filename}.pub")
    `rm #{filename} && rm #{filename}.pub`
  end

end
