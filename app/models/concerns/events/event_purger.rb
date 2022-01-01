module Events
  module EventPurger
    extend ActiveSupport::Concern

    class_methods do

      ## Cleanup old logs
      def clean!
        clean_containers!
        clean_container_services!
        clean_sftp!
        clean_system!
        clean_volumes!
        true
      end

      # Find stuck / stale jobs and cancel them
      def clean_event_status!
        where("updated_at < ? AND (status = 'running' OR status = 'pending')", 2.hours.ago).update_all(
          status: 'cancelled',
          state_reason: "Cancelled by system",
          event_code: "d7ef6c0313fb1375"
        )
      end

      private

      def clean_system!
        where(locale: "node.ports.open").where("created_at < ?", 30.days.ago).delete_all
      end

      def clean_container_services!
        left_outer_joins(:container_services).where(
          deployment_container_services: { id: nil }
        ).where(
          Arel.sql(
            %q(event_logs.locale IN ('service.building', 'service.building_1', 'service.removing', 'service.removing_1', 'service.resizing', 'service.resizing_1', 'service.scaling', 'service.errors.scale', 'service.errors.resize', 'service.errors.delete'))
          )
        ).delete_all
      end

      def clean_containers!
        left_outer_joins(:containers).where(
          deployment_containers: { id: nil }
        ).where(
          Arel.sql(
            %q(NOT (locale_keys @> '{"label":"SFTP"}'))
          )
        ).where(
          Arel.sql(
            %q(event_logs.locale IN ('container.start', 'container.stop', 'container.restart', 'container.delete', 'container.build', 'container.rebuild', 'container.errors.general_provision', 'container.errors.resize'))
          )
        ).delete_all
      end

      def clean_sftp!
        left_outer_joins(:sftp_containers).where(
          deployment_sftps: { id: nil }
        ).where(
          Arel.sql(%q(locale_keys @> '{"label":"SFTP"}'))
        ).where(
          Arel.sql(%q(event_logs.locale IN ('container.start', 'container.stop', 'container.restart', 'container.delete', 'container.build')))
        ).delete_all
      end

      def clean_volumes!
        left_outer_joins(:volumes).where(volumes: { id: nil }).where(locale: "volumes.imported").delete_all
      end

    end

  end
end
