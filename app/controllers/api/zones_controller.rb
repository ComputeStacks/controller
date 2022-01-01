##
# Zones Controller
class Api::ZonesController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :dns_read }, only: %i[index show], unless: :current_user

  before_action :find_zone, except: %i[ index ]

  ##
  # List all zones
  #
  # `GET /api/zones`
  #
  # **OAuth AuthorizationRequired**: `dns_read`
  #
  # * `zones`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def index
    @dns_zones = paginate Dns::Zone.find_all_for(current_user).order(:created_at)
  end

  ##
  # View zone
  #
  # `GET /api/zones/{id}`
  #
  # **OAuth AuthorizationRequired**: `dns_read`
  #
  # * `zone`:
  #     * `id`: Integer
  #     * `name`: String
  #     * `records`: Object
  #         * `A`: Array
  #         * `...`
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  # @example
  #    {
  #      "zone": {
  #        "id": 2,
  #        "name": "mytestdomain.net",
  #        "created_at": "2019-08-26T17:22:39.333Z",
  #        "updated_at": "2019-08-26T17:22:39.333Z",
  #        "records": {
  #          "A": [],
  #          "AAAA": [],
  #          "CAA": [],
  #          "CNAME": [],
  #          "DS": [],
  #          "HINFO": [],
  #          "MX": [],
  #          "NAPTR": [],
  #          "NS": [
  #            {
  #              "ttl": 86400,
  #              "zone_id": "mytestdomain.net",
  #              "type": "NS",
  #              "name": "mytestdomain.net",
  #              "hostname": "ns1.auto-dns.com"
  #            },
  #            {
  #              "ttl": 86400,
  #              "zone_id": "mytestdomain.net",
  #              "type": "NS",
  #              "name": "mytestdomain.net",
  #              "hostname": "ns2.auto-dns.com"
  #            },
  #            {
  #              "ttl": 86400,
  #              "zone_id": "mytestdomain.net",
  #              "type": "NS",
  #              "name": "mytestdomain.net",
  #              "hostname": "ns3.autodns.nl"
  #            },
  #            {
  #              "ttl": 86400,
  #              "zone_id": "mytestdomain.net",
  #              "type": "NS",
  #              "name": "mytestdomain.net",
  #              "hostname": "ns4.autodns.nl"
  #            }
  #          ],
  #          "PTR": [],
  #          "SRV": [],
  #          "SOA": [
  #            {
  #              "ttl": 86400,
  #              "zone_id": "mytestdomain.net",
  #              "type": "SOA",
  #              "refresh": 43200,
  #              "retry": 7200,
  #              "expire": 1209600,
  #              "email": "dns@usr.cloud",
  #              "default": 86400
  #            }
  #          ],
  #          "SSHFP": [],
  #          "TLSA": [],
  #          "TXT": []
  #        }
  #      }
  #    }

  def show
    zone_load = @dns_zone.state_load!
    @records = zone_load.records
  end

  private

  def find_zone
    @dns_zone = Dns::Zone.find_for_edit current_user, id: params[:id]
    return api_obj_missing if @dns_zone.nil?
    @dns_zone.current_user = current_user
  end

end
