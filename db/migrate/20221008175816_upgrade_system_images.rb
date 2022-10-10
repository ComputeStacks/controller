class UpgradeSystemImages < ActiveRecord::Migration[7.0]
  def change

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
        skip_tag_validation: true
      ) unless mysql.image_variants.where(registry_image_tag: "10.9").exists?

      mysql.image_variants.create!(
        label: "10.8",
        registry_image_tag: "10.8",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true
      ) unless mysql.image_variants.where(registry_image_tag: "10.8").exists?

      mysql.image_variants.create!(
        label: "10.7",
        registry_image_tag: "10.7",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true
      ) unless mysql.image_variants.where(registry_image_tag: "10.7").exists?

      mysql.image_variants.create!(
        label: "10.6",
        registry_image_tag: "10.6",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true
      ) unless mysql.image_variants.where(registry_image_tag: "10.6").exists?

      mysql.image_variants.create!(
        label: "10.5",
        registry_image_tag: "10.5",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true
      ) unless mysql.image_variants.where(registry_image_tag: "10.5").exists?

    end

    # PHP
    unless ContainerImage.where(name: 'php').exists?
      php = ContainerImage.find_by(name: 'php-7-4')

      if php
        php.update name: 'php', label: 'PHP'
        php.image_variants.each do |i|
          i.update_column :is_default, false
        end
        php.image_variants.create!(
          label: "php8.1-litespeed",
          registry_image_tag: "php8.1-litespeed",
          validated_tag: true,
          validated_tag_updated: Time.now,
          is_default: true,
          skip_tag_validation: true
        ) unless php.image_variants.where(registry_image_tag: "php8.1-litespeed").exists?

        php.image_variants.create!(
          label: "php8.0-litespeed",
          registry_image_tag: "php8.0-litespeed",
          validated_tag: true,
          validated_tag_updated: Time.now,
          skip_tag_validation: true
        ) unless php.image_variants.where(registry_image_tag: "php8.0-litespeed").exists?

        php.image_variants.create!(
          label: "php7.4-litespeed",
          registry_image_tag: "php7.4-litespeed",
          validated_tag: true,
          validated_tag_updated: Time.now,
          skip_tag_validation: true
        ) unless php.image_variants.where(registry_image_tag: "php7.4-litespeed").exists?

        php.image_variants.create!(
          label: "php7.3-litespeed",
          registry_image_tag: "php7.4-litespeed",
          validated_tag: true,
          validated_tag_updated: Time.now,
          skip_tag_validation: true
        ) unless php.image_variants.where(registry_image_tag: "php7.3-litespeed").exists?
      end

    end

    # Postgres
    if ContainerImage.where(name: 'postgres').exists?
      pg = ContainerImage.find_by(name: 'postgres')
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
        label: "11-bullseye",
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
    wp = ContainerImage.find_by name: 'wordpress', registry_image_path: "cmptstks/wordpress"
    if wp
      wp.image_variants.each do |i|
        i.update_column :is_default, false
      end
      wp.image_variants.create!(
        label: "php8.0-litespeed",
        registry_image_tag: "php8.0-litespeed",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true
      ) unless wp.image_variants.where(registry_image_tag: "php8.0-litespeed").exists?

      wp.image_variants.create!(
        label: "php8.1-litespeed",
        registry_image_tag: "php8.1-litespeed",
        validated_tag: true,
        validated_tag_updated: Time.now,
        is_default: true,
        skip_tag_validation: true
      ) unless wp.image_variants.where(registry_image_tag: "php8.1-litespeed").exists?

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

  end
end
