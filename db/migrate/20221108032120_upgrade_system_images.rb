class UpgradeSystemImages < ActiveRecord::Migration[7.0]
  def change

    gh_image_provider = ContainerImageProvider.find_by(name: "Github")
    if gh_image_provider.nil? # shouldn't happen
      gh_image_provider = ContainerImageProvider.create!(
        name: "Github",
        is_default: false,
        hostname: "ghcr.io"
      )
    end

    # MariaDB
    unless ContainerImage.where(name: 'mariadb').exists?
      mysql = ContainerImage.find_by(name: 'mariadb-105')

      mysql.update name: 'mariadb', label: 'MariaDB'

      mysql.image_variants.each do |i|
        i.update_column :is_default, false
      end

      mysql.image_variants.create!(
        label: "10.9",
        registry_image_tag: "10.9",
        validated_tag: true,
        validated_tag_updated: Time.now,
        is_default: true,
        skip_tag_validation: true,
        version: 0
      ) unless mysql.image_variants.where(registry_image_tag: "10.9").exists?

      mysql.image_variants.create!(
        label: "10.8",
        registry_image_tag: "10.8",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true,
        version: 1
      ) unless mysql.image_variants.where(registry_image_tag: "10.8").exists?

      mysql.image_variants.create!(
        label: "10.7",
        registry_image_tag: "10.7",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true,
        version: 2
      ) unless mysql.image_variants.where(registry_image_tag: "10.7").exists?

      mysql.image_variants.create!(
        label: "10.6",
        registry_image_tag: "10.6",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true,
        version: 3
      ) unless mysql.image_variants.where(registry_image_tag: "10.6").exists?

      mysql.image_variants.create!(
        label: "10.5",
        registry_image_tag: "10.5",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true,
        version: 4
      ) unless mysql.image_variants.where(registry_image_tag: "10.5").exists?

      mysql.image_variants.create!(
        label: "10.4",
        registry_image_tag: "10.4",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true,
        version: 5
      ) unless mysql.image_variants.where(registry_image_tag: "10.4").exists?

    end

    # phpMyAdmin
    pma = ContainerImage.find_by registry_image_path: "cmptstks/phpmyadmin"
    if pma
      pma.update container_image_provider: gh_image_provider, registry_image_path: "computestacks/cs-docker-pma"
    end

    # PHP
    php = ContainerImage.find_by name: "php" # newer-style
    if php.nil?
      php = ContainerImage.find_by(name: 'php-7-4')
      if php
        php.update container_image_provider: gh_image_provider, name: 'php', label: 'PHP', registry_image_path: "computestacks/cs-docker-php"
        php.image_variants.each do |i|
          i.update_column :is_default, false
        end
        php.image_variants.create!(
          label: "8.1",
          registry_image_tag: "8.1-litespeed",
          validated_tag: true,
          validated_tag_updated: Time.now,
          is_default: true,
          skip_tag_validation: true,
          version: 0,
          after_migrate: "/usr/local/bin/migrate_php_version",
          rollback_migrate: "echo \"Please rebuild container and try again\""
        ) unless php.image_variants.where(registry_image_tag: "php8.1-litespeed").exists?

        php.image_variants.create!(
          label: "8.0",
          registry_image_tag: "8.0-litespeed",
          validated_tag: true,
          validated_tag_updated: Time.now,
          skip_tag_validation: true,
          version: 1,
          after_migrate: "/usr/local/bin/migrate_php_version",
          rollback_migrate: "echo \"Please rebuild container and try again\""
        ) unless php.image_variants.where(registry_image_tag: "php8.0-litespeed").exists?

        php_74 = php.image_variants.find_by(registry_image_tag: "7.4-litespeed")
        if php_74
          php_74.update version: 2, after_migrate: "/usr/local/bin/migrate_php_version", rollback_migrate: "echo \"Please rebuild container and try again\""
        else
          php.image_variants.create!(
            label: "7.4",
            registry_image_tag: "7.4-litespeed",
            validated_tag: true,
            validated_tag_updated: Time.now,
            skip_tag_validation: true,
            version: 2,
            after_migrate: "/usr/local/bin/migrate_php_version",
            rollback_migrate: "echo \"Please rebuild container and try again\""
          )
        end

        php_73 = php.image_variants.find_by(registry_image_tag: "7.3-litespeed")
        if php_73
          php_73.update version: 3, after_migrate: "/usr/local/bin/migrate_php_version", rollback_migrate: "echo \"Please rebuild container and try again\""
        else
          php.image_variants.create!(
            label: "7.3",
            registry_image_tag: "7.3-litespeed",
            validated_tag: true,
            validated_tag_updated: Time.now,
            skip_tag_validation: true,
            version: 3,
            after_migrate: "/usr/local/bin/migrate_php_version",
            rollback_migrate: "echo \"Please rebuild container and try again\""
          )
        end
      end
    else
      php.update container_image_provider: gh_image_provider, registry_image_path: "computestacks/cs-docker-php"
    end

    # Postgres
    pg = ContainerImage.find_by(name: 'postgres')
    pg = ContainerImage.find_by(name: "postgres-12") if pg.nil?
    unless pg.nil?
      pg.image_variants.each do |i|
        i.update_column :is_default, false
      end
      pg.image_variants.create!(
        label: "14",
        registry_image_tag: "14",
        validated_tag: true,
        validated_tag_updated: Time.now,
        is_default: true,
        skip_tag_validation: true
      ) unless pg.image_variants.where(registry_image_tag: "14").exists?
      pg.image_variants.create!(
        label: "13",
        registry_image_tag: "13",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true
      ) unless pg.image_variants.where(registry_image_tag: "13").exists?
      unless pg.image_variants.where(registry_image_tag: "12-alpine").exists?
        pg.image_variants.create!(
          label: "12",
          registry_image_tag: "12",
          validated_tag: true,
          validated_tag_updated: Time.now,
          skip_tag_validation: true
        ) unless pg.image_variants.where(registry_image_tag: "12").exists?
      end
      pg.image_variants.create!(
        label: "11",
        registry_image_tag: "11-bullseye",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true
      ) unless pg.image_variants.where(registry_image_tag: "11-bullseye").exists?
      pg.image_variants.create!(
        label: "10",
        registry_image_tag: "10-bullseye",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true
      ) unless pg.image_variants.where(registry_image_tag: "10-bullseye").exists?
    end

    # Wordpress
    wp = ContainerImage.find_by name: 'wordpress' # in case provider has custom wordpress image...
    if wp && %w(computestacks/cs-docker-wordpress cmptstks/wordpress).include?(wp.registry_image_path)
      wp.update container_image_provider: gh_image_provider, registry_image_path: "computestacks/cs-docker-wordpress"
      wp.image_variants.each do |i|
        i.update_column :is_default, false
      end

      wp.image_variants.create!(
        label: "php 8.1",
        registry_image_tag: "php8.1-litespeed",
        validated_tag: true,
        validated_tag_updated: Time.now,
        is_default: true,
        skip_tag_validation: true,
        version: 0,
        after_migrate: "/usr/local/bin/migrate_php_version",
        rollback_migrate: "echo \"Please rebuild container and try again\""
      ) unless wp.image_variants.where(registry_image_tag: "php8.1-litespeed").exists?

      wp.image_variants.create!(
        label: "php 8.0",
        registry_image_tag: "php8.0-litespeed",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true,
        version: 1,
        after_migrate: "/usr/local/bin/migrate_php_version",
        rollback_migrate: "echo \"Please rebuild container and try again\""
      ) unless wp.image_variants.where(registry_image_tag: "php8.0-litespeed").exists?

      wp_74 = wp.image_variants.find_by(registry_image_tag: "php7.4-litespeed")
      if wp_74
        wp_74.update version: 2, after_migrate: "/usr/local/bin/migrate_php_version", rollback_migrate: "echo \"Please rebuild container and try again\""
      end

      wp_73 = wp.image_variants.find_by(registry_image_tag: "php7.3-litespeed")
      if wp_73
        wp_73.update version: 3, after_migrate: "/usr/local/bin/migrate_php_version", rollback_migrate: "echo \"Please rebuild container and try again\""
      end

      unless ContainerImageCollection.where(label: 'Wordpress').exists?
        mysql = ContainerImage.find_by(name: 'mariadb')
        if mysql
          wpc = ContainerImageCollection.create!( label: 'Wordpress', active: true )
          wpc.container_images << mysql
          wpc.container_images << wp
          wp.update active: false # Only visible in collection
        end
      end

    end

    # WHMCS
    whmcs = ContainerImage.find_by registry_image_path: "cmptstks/whmcs"
    if whmcs
      whmcs.update container_image_provider: gh_image_provider, registry_image_path: "computestacks/cs-docker-whmcs"
    end

  end
end
