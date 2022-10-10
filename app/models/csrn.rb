##
# CSRN - ComputeStacks Resource Name
#
# csrn:<partition>:<service>:<friendly-name>:<object-id>
#
# The friendly name will be dynamic and can be changed without affecting lookups.
#
# Partitions:
# * caas => image, projects, containers, ...
# * billing => subscriptions, billing plans, ...
# * ident => users, auth, ...
#
# Services:
# * template => image, image_variant, params, ...
# * project => container, domain, ingress rules, ...
# * subscription => billing events, usage items, ...
#
class Csrn

  attr_accessor :id,
                :obj

  def initialize(obj)
    self.obj = obj
    self.id = obj.csrn
  end

  class << self

    def locate(rn)

      id = rn.split(":")
      return nil unless id[0] == "csrn"

      case id[1]
      when "caas"
        case id[2]
        when "project"
          case id[3]
          when "cidr"
            Network::Cidr.find_by id: id[5]
          when "container"
            Deployment::Container.find_by id: id[5]
          when "domain"
            Deployment::ContainerDomain.find_by id: id[5]
          when "ingress"
            Network::IngressRule.find_by id: id[5]
          when "root"
            Deployment.find_by id: id[5]
          when "service"
            Deployment::ContainerService.find_by id: id[5]
          when "shell"
            Deployment::Sftp.find_by id: id[5]
          when "vol"
            Volume.find_by id: id[5]
          end
        when "template"
          case id[3]
          when "env"
            ContainerImage::EnvParam.find_by id: id[5]
          when "image"
            ContainerImage.find_by id: id[5]
          when "image_variant"
            ContainerImage::ImageVariant.find_by id: id[5]
          when "ingress"
            ContainerImage::IngressParam.find_by id: id[5]
          when "setting"
            ContainerImage::SettingParam.find_by id: id[5]
          when "vol"
            ContainerImage::VolumeParam.find_by id: id[5]
          end
        end
      when "billing"
        case id[2]
        when "subscription"
          case id[3]
          when "root"
            Subscription.find_by id: id[5]
          end
        end
      when "ident"
        case id[2]
        when "account"
          case id[3]
          when "user"
            User.find_by id: id[5]
          end
        end
      else
        nil
      end

    end

  end

end
